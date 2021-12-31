/*
 * BSD 2-Clause License
 *
 * Copyright (c) 2021, Christoph Neuhauser
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <algorithm>

#include <boost/filesystem.hpp>
#include <tracy/Tracy.hpp>

#include <Utils/AppSettings.hpp>
#include <Utils/File/Logfile.hpp>
#include <Utils/File/FileUtils.hpp>
#include <Utils/File/FileLoader.hpp>
#include <ImGui/ImGuiWrapper.hpp>
#include <ImGui/imgui_custom.h>
#include <ImGui/imgui_stdlib.h>
#ifdef USE_VULKAN_INTEROP
#include <Graphics/Vulkan/Render/Renderer.hpp>
#endif

#include "Utils/IndexMesh.hpp"
#include "../LineDataFlow.hpp"
#include "StreamlineSeeder.hpp"
#include "StreamlineTracingGrid.hpp"
#include "Loader/StructuredGridVtkLoader.hpp"
#include "Loader/RbcBinFileLoader.hpp"
#include "StreamlineTracingRequester.hpp"

StreamlineTracingRequester::StreamlineTracingRequester(sgl::TransferFunctionWindow& transferFunctionWindow)
        : transferFunctionWindow(transferFunctionWindow) {
    streamlineSeeders.insert(std::make_pair(
            StreamlineSeedingStrategy::VOLUME, StreamlineSeederPtr(new StreamlineVolumeSeeder)));
    streamlineSeeders.insert(std::make_pair(
            StreamlineSeedingStrategy::PLANE, StreamlineSeederPtr(new StreamlinePlaneSeeder)));
    streamlineSeeders.insert(std::make_pair(
            StreamlineSeedingStrategy::MAX_HELICITY_FIRST, StreamlineSeederPtr(new StreamlinePlaneSeeder))); // TODO
    guiTracingSettings.seeder = streamlineSeeders[guiTracingSettings.streamlineSeedingStrategy];

    lineDataSetsDirectory = sgl::AppSettings::get()->getDataDirectory() + "LineDataSets/";
    loadGridDataSetList();
    requesterThread = std::thread(&StreamlineTracingRequester::mainLoop, this);
}

StreamlineTracingRequester::~StreamlineTracingRequester() {
    join();

    if (cachedGrid) {
        delete cachedGrid;
        cachedGrid = nullptr;
    }

    requestLineData = {};
    replyLineData = {};
}

void StreamlineTracingRequester::loadGridDataSetList() {
    gridDataSetNames.clear();
    gridDataSetFilenames.clear();
    gridDataSetNames.emplace_back("Local file...");

    std::string filename = lineDataSetsDirectory + "flow_grids.json";
    if (sgl::FileUtils::get()->exists(filename)) {
        // Parse the passed JSON file.
        std::ifstream jsonFileStream(filename.c_str());
        Json::CharReaderBuilder builder;
        JSONCPP_STRING errorString;
        Json::Value root;
        if (!parseFromStream(builder, jsonFileStream, &root, &errorString)) {
            sgl::Logfile::get()->writeError(errorString);
            return;
        }
        jsonFileStream.close();

        Json::Value sources = root["grids"];
        for (Json::Value::const_iterator sourceIt = sources.begin(); sourceIt != sources.end(); ++sourceIt) {
            DataSetInformation dataSetInformation;
            Json::Value source = *sourceIt;

            gridDataSetNames.push_back(source["name"].asString());
            gridDataSetFilenames.push_back(source["filename"].asString());
        }
    }
}

void StreamlineTracingRequester::renderGui() {
    sgl::ImGuiWrapper::get()->setNextWindowStandardPosSize(3072, 1146, 760, 628);
    if (ImGui::Begin("Streamline Tracer", &showWindow)) {
        {
            std::lock_guard<std::mutex> replyLock(gridInfoMutex);
            if (newGridLoaded) {
                newGridLoaded = false;
                for (auto& it : streamlineSeeders) {
                    it.second->setNewGridBox(gridBox);
                }
            }
        }

        bool changed = false;
        if (ImGui::Combo(
                "Data Set", &selectedGridDataSetIndex, gridDataSetNames.data(),
                int(gridDataSetNames.size()))) {
            if (selectedGridDataSetIndex >= 1) {
                const std::string pathString = gridDataSetFilenames.at(selectedGridDataSetIndex - 1);
#ifdef _WIN32
                bool isAbsolutePath =
                    (pathString.size() > 1 && pathString.at(1) == ':')
                    || boost::starts_with(pathString, "/") || boost::starts_with(pathString, "\\");
#else
                bool isAbsolutePath =
                        boost::starts_with(pathString, "/");
#endif
                if (isAbsolutePath) {
                    gridDataSetFilename = pathString;
                } else {
                    gridDataSetFilename = lineDataSetsDirectory + pathString;
                }
                changed = true;
            }
        }
        if (selectedGridDataSetIndex == 0) {
            ImGui::InputText("##griddatasetfilenamelabel", &gridDataSetFilename);
            ImGui::SameLine();
            if (ImGui::Button("Load File")) {
                changed = true;
            }
        }

        if (ImGui::Combo(
                "Primitive Type", (int*)&guiTracingSettings.flowPrimitives,
                FLOW_PRIMITIVE_NAMES, IM_ARRAYSIZE(FLOW_PRIMITIVE_NAMES))) {
            changed = true;
        }

        if (!guiTracingSettings.seeder->getIsRegular()) {
            if (ImGui::SliderIntPowerOfTwoEdit(
                    "#Primitives", &guiTracingSettings.numPrimitives,
                    1, 1048576) == ImGui::EditMode::INPUT_FINISHED) {
                changed = true;
            }
        }

        if (ImGui::Combo(
                "Seeding Strategy", (int*)&guiTracingSettings.streamlineSeedingStrategy,
                STREAMLINE_SEEDING_STRATEGY_NAMES, IM_ARRAYSIZE(STREAMLINE_SEEDING_STRATEGY_NAMES))) {
            guiTracingSettings.seeder = streamlineSeeders[guiTracingSettings.streamlineSeedingStrategy];
            changed = true;
        }

        if (guiTracingSettings.seeder->renderGui()) {
            changed = true;
        }

        if (ImGui::CollapsingHeader(
                "Advanced Settings", nullptr, ImGuiTreeNodeFlags_DefaultOpen)) {
            if (ImGui::SliderFloat(
                    "Time Step Scale", &guiTracingSettings.timeStepScale, 0.1f, 10.0f,
                    "%.1f", ImGuiSliderFlags_Logarithmic)) {
                changed = true;
            }
            if (ImGui::SliderInt(
                    "Max. #Iterations", &guiTracingSettings.maxNumIterations, 10, 10000)) {
                changed = true;
            }
            if (ImGui::SliderFloat(
                    "Termination Dist. (*1e-6)", &guiTracingSettings.terminationDistance, 0.01f, 100.0f,
                    "%.2f", ImGuiSliderFlags_Logarithmic)) {
                changed = true;
            }
            if (ImGui::Combo(
                    "Integration Method", (int*)&guiTracingSettings.integrationMethod,
                    STREAMLINE_INTEGRATION_METHOD_NAMES,
                    IM_ARRAYSIZE(STREAMLINE_INTEGRATION_METHOD_NAMES))) {
                changed = true;
            }
        }

        if (changed) {
            requestNewData();
        }
    }
    ImGui::End();
}

void StreamlineTracingRequester::setLineTracerSettings(const SettingsMap& settings) {
    // TODO
    /*bool changed = false;

    std::string datasetName;
    if (settings.getValueOpt("dataset", datasetName)) {
        for (int i = 0; i < int(gridDataSetNames.size()); i++) {
            if (datasetName == gridDataSetNames.at(i)) {
                selectedGridDataSetIndex = i + 1;
                const std::string pathString = gridDataSetFilenames.at(selectedGridDataSetIndex - 1);
#ifdef _WIN32
                bool isAbsolutePath =
                    (pathString.size() > 1 && pathString.at(1) == ':')
                    || boost::starts_with(pathString, "/") || boost::starts_with(pathString, "\\");
#else
                bool isAbsolutePath =
                        boost::starts_with(pathString, "/");
#endif
                if (isAbsolutePath) {
                    gridDataSetFilename = pathString;
                } else {
                    gridDataSetFilename = lineDataSetsDirectory + pathString;
                }
                changed = true;
                break;
            }
        }
    }

    changed |= settings.getValueOpt("use_isosurface", gui_StreamlineTracingSettings.show_iso_surface);
    changed |= settings.getValueOpt("camera_fov", gui_StreamlineTracingSettings.camera_fov_deg);
    changed |= settings.getValueOpt("camera_position", gui_StreamlineTracingSettings.camera_position);
    changed |= settings.getValueOpt("camera_look_at", gui_StreamlineTracingSettings.camera_look_at);
    changed |= settings.getValueOpt("res_x", gui_StreamlineTracingSettings.res_x);
    changed |= settings.getValueOpt("res_y", gui_StreamlineTracingSettings.res_y);
    changed |= settings.getValueOpt("samples_per_pixel", gui_StreamlineTracingSettings.samples_per_pixel);
    changed |= settings.getValueOpt("extinction", gui_StreamlineTracingSettings.extinction);
    changed |= settings.getValueOpt("scattering_albedo", gui_StreamlineTracingSettings.scattering_albedo);
    changed |= settings.getValueOpt("g", gui_StreamlineTracingSettings.g);

    if (changed) {
        requestNewData();
    }*/
}

void StreamlineTracingRequester::setDatasetFilename(const std::string& newDatasetFilename) {
    bool isDataSetInList = false;
    for (int i = 0; i < int(gridDataSetFilenames.size()); i++) {
        auto newDataSetPath = boost::filesystem::absolute(newDatasetFilename);
        auto currentDataSetPath = boost::filesystem::absolute(
                lineDataSetsDirectory + gridDataSetFilenames.at(i));
        if (boost::filesystem::equivalent(newDataSetPath, currentDataSetPath)) {
            selectedGridDataSetIndex = i + 1;
            const std::string pathString = gridDataSetFilenames.at(selectedGridDataSetIndex - 1);
#ifdef _WIN32
            bool isAbsolutePath =
                    (pathString.size() > 1 && pathString.at(1) == ':')
                    || boost::starts_with(pathString, "/") || boost::starts_with(pathString, "\\");
#else
            bool isAbsolutePath =
                    boost::starts_with(pathString, "/");
#endif
            if (isAbsolutePath) {
                gridDataSetFilename = pathString;
            } else {
                gridDataSetFilename = lineDataSetsDirectory + pathString;
            }
            isDataSetInList = true;
            break;
        }
    }

    if (!isDataSetInList) {
        selectedGridDataSetIndex = 0;
        gridDataSetFilename = newDatasetFilename;
    }

    requestNewData();
}

void StreamlineTracingRequester::requestNewData() {
    if (gridDataSetFilename.empty()) {
        return;
    }

    StreamlineTracingSettings request = guiTracingSettings;
    request.seeder = StreamlineSeederPtr(guiTracingSettings.seeder->copy());
    request.dataSourceFilename = boost::filesystem::absolute(gridDataSetFilename).generic_string();

    queueRequestStruct(request);
    isProcessingRequest = true;
}

bool StreamlineTracingRequester::getHasNewData(DataSetInformation& dataSetInformation, LineDataPtr& lineData) {
    if (getReply(lineData)) {
        isProcessingRequest = false;
        return true;
    }
    return false;
}

void StreamlineTracingRequester::queueRequestStruct(const StreamlineTracingSettings& request) {
    {
        std::lock_guard<std::mutex> lock(replyMutex);
        workerTracingSettings = request;
        requestLineData = LineDataPtr(new LineDataFlow(transferFunctionWindow));
        hasRequest = true;
    }
    hasRequestConditionVariable.notify_all();
}

bool StreamlineTracingRequester::getReply(LineDataPtr& lineData) {
    bool hasReply;
    {
        std::lock_guard<std::mutex> lock(replyMutex);
        hasReply = this->hasReply;
        if (hasReply) {
            lineData = replyLineData;
        }

        // Now, new requests can be worked on.
        this->hasReply = false;
        // this->replyMessage.clear();
        this->replyLineData = LineDataPtr();
    }
    hasReplyConditionVariable.notify_all();
    return hasReply;
}

void StreamlineTracingRequester::join() {
    if (!programIsFinished) {
        {
            std::lock_guard<std::mutex> lock(requestMutex);
            programIsFinished = true;
            hasRequest = true;

            {
                std::lock_guard<std::mutex> lock(replyMutex);
                this->hasReply = false;
                // this->replyMessage.clear();
            }
            hasReplyConditionVariable.notify_all();
        }
        hasRequestConditionVariable.notify_all();
        if (requesterThread.joinable()) {
            requesterThread.join();
        }
    }
}

void StreamlineTracingRequester::mainLoop() {
#ifdef TRACY_ENABLE
    tracy::SetThreadName("StreamlineTracingRequester");
#endif

    while (true) {
        std::unique_lock<std::mutex> requestLock(requestMutex);
        hasRequestConditionVariable.wait(requestLock, [this] { return hasRequest; });

        if (programIsFinished) {
            break;
        }

        if (hasRequest) {
            StreamlineTracingSettings request = workerTracingSettings;
            std::shared_ptr<LineDataFlow> lineData = std::static_pointer_cast<LineDataFlow>(requestLineData);
            hasRequest = false;
            isProcessingRequest = true;
            requestLock.unlock();

            traceLines(request, lineData);

            std::lock_guard<std::mutex> replyLock(replyMutex);
            hasReply = true;

            replyLineData = lineData;
            isProcessingRequest = false;
        }
    }
}

void StreamlineTracingRequester::traceLines(
        StreamlineTracingSettings& request, std::shared_ptr<LineDataFlow>& lineData) {
    if (cachedGridFilename != request.dataSourceFilename) {
        if (cachedGrid) {
            delete cachedGrid;
            cachedGrid = nullptr;
        }
        cachedGridFilename = request.dataSourceFilename;

        cachedGrid = new StreamlineTracingGrid;
        if (boost::ends_with(request.dataSourceFilename, ".vtk")) {
            StructuredGridVtkLoader::load(request.dataSourceFilename, cachedGrid);
        } else if (boost::ends_with(request.dataSourceFilename, ".bin")) {
            RbcBinFileLoader::load(request.dataSourceFilename, cachedGrid);
        }

        {
            std::lock_guard<std::mutex> replyLock(gridInfoMutex);
            newGridLoaded = true;
            gridBox = cachedGrid->getBox();
        }
    }

    Trajectories trajectories = cachedGrid->traceStreamlines(request);
    normalizeTrajectoriesVertexPositions(trajectories, nullptr);

    for (size_t i = 0; i < trajectories.size(); i++) {
        if (trajectories.at(i).positions.empty()) {
            trajectories.erase(trajectories.begin() + long(i));
            i--;
        }
    }

    lineData->fileNames = { request.dataSourceFilename };
    lineData->attributeNames = cachedGrid->getScalarAttributeNames();
    lineData->setTrajectoryData(trajectories);
}
