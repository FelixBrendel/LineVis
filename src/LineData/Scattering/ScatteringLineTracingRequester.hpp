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

#ifndef LINEVIS_SCATTERINGLINETRACINGREQUESTER_HPP
#define LINEVIS_SCATTERINGLINETRACINGREQUESTER_HPP

#include <thread>
#include <condition_variable>

#include "Loaders/DataSetList.hpp"
#include "LineDataScattering.hpp"

/**
 * Traces lines inside a scalar field while simulation scattering.
 * A LineDataVolume object is generated containing the scalar field and the lines.
 */
class ScatteringLineTracingRequester {
public:
    ScatteringLineTracingRequester(
            sgl::TransferFunctionWindow& transferFunctionWindow
#ifdef USE_VULKAN_INTEROP
            , sgl::vk::Renderer* rendererVk
#endif
    );
    ~ScatteringLineTracingRequester();
    void renderGui();
    bool getHasNewData(DataSetInformation& dataSetInformation, LineDataPtr& lineData);

    /**
     * @return Whether a request is currently processed (for UI progress spinner).
     */
    inline bool getIsProcessingRequest() const { return isProcessingRequest; }

private:
    void loadGridDataSetList();
    void requestNewData();

    /// The main loop of the requester thread.
    void mainLoop();
    /// Waits for the requester thread to terminate.
    void join();

    /**
     * Queues the request for tracing .
     * @param request The message to queue.
     */
    void queueRequestJson(const Json::Value& request);
    /**
     * Checks if a reply was received to a request. If a reply was received, it is stored in reply.
     * @param reply Where to store the reply (if one was received).
     * @return Whether a reply was received.
     */
    bool getReplyJson(Json::Value& reply, LineDataPtr& lineData);

    /**
     * @param request Information for the requested tracing of lines scattered in the grid.
     * @return A reply to the request.
     */
    Json::Value traceLines(const Json::Value& request, std::shared_ptr<LineDataScattering>& lineData);

    sgl::TransferFunctionWindow& transferFunctionWindow;
#ifdef USE_VULKAN_INTEROP
    sgl::vk::Renderer* rendererVk = nullptr;
#endif

    std::thread requesterThread;
    std::condition_variable hasRequestConditionVariable;
    std::condition_variable hasReplyConditionVariable;
    std::mutex requestMutex;
    std::mutex replyMutex;

    bool programIsFinished = false;
    bool hasRequest = false;
    bool hasReply = false;
    bool isProcessingRequest = false;
    Json::Value requestMessage;
    Json::Value replyMessage;
    LineDataPtr requestLineData;
    LineDataPtr replyLineData;

    // Line tracing settings.
    int numLinesToTrace = 1000;
    float extinctionCoefficient = 10.0f;

    // Cache.
    std::string cachedGridDataSetFilename;
    float* cachedGridData = nullptr;
    uint32_t cachedGridSizeX = 0, cachedGridSizeY = 0, cachedGridSizeZ = 0;
    float cachedVoxelSizeX = 0.0f, cachedVoxelSizeY = 0.0f, cachedVoxelSizeZ = 0.0f;

    // GUI data.
    bool showWindow = true;
    std::string gridDataSetFilename;
    std::vector<std::string> gridDataSetNames;
    std::vector<std::string> gridDataSetFilenames;
    int selectedGridDataSetIndex = 0;
};

#endif //LINEVIS_SCATTERINGLINETRACINGREQUESTER_HPP
