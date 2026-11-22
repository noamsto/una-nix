#ifndef __SERVICE_HPP__
#define __SERVICE_HPP__

#include "SDK/Kernel/KernelProviderService.hpp"
#include "SDK/SensorLayer/SensorConnection.hpp"
#include "SDK/SensorLayer/SensorDataBatch.hpp"
#include "SDK/Interfaces/IFileSystem.hpp"

#include <memory>

/**
 * Overnight sensor logger.
 *
 * Autostarts, connects the low-rate sensors that sleep/wake detection needs,
 * and appends one CSV row per event to LOG_PATH. Deliberately no GUI and no
 * raw accelerometer: the point is to find out what an all-night background
 * service costs in battery before any algorithm is written.
 */
class Service
{
public:
    Service(SDK::Kernel& kernel);
    virtual ~Service() = default;

    void run();

private:
    static constexpr const char* LOG_DIR  = "/apps/logger";
    static constexpr const char* LOG_PATH = "/apps/logger/session.csv";

    // Rows are buffered and flushed in batches: an open-write-close per event
    // would dominate both power draw and flash wear over an eight-hour night.
    static constexpr size_t FLUSH_THRESHOLD = 64;

    SDK::Kernel&            mKernel;
    SDK::Sensor::Connection mSensorWristMotion;
    SDK::Sensor::Connection mSensorMotionDetect;
    SDK::Sensor::Connection mSensorActivityRecognition;
    SDK::Sensor::Connection mSensorHeartRate;
    SDK::Sensor::Connection mSensorBattery;

    std::unique_ptr<SDK::Interface::IFile> mFile;
    size_t                                 mPendingRows;

    void connectSensors();
    void disconnectSensors();

    void openLog();
    void appendRow(const char* sensor, uint32_t timeMs, float a, float b);
    void flush();

    void onSensorData(uint16_t handle, SDK::Sensor::DataBatch& data);
};

#endif
