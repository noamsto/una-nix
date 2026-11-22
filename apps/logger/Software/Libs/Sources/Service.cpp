#include "SDK/SensorLayer/DataParsers/SensorDataParserWristMotion.hpp"
#include "SDK/SensorLayer/DataParsers/SensorDataParserMotionDetect.hpp"
#include "SDK/SensorLayer/DataParsers/SensorDataParserActivityRecognition.hpp"
#include "SDK/SensorLayer/DataParsers/SensorDataParserHeartRate.hpp"
#include "SDK/SensorLayer/DataParsers/SensorDataParserBatteryLevel.hpp"
#include "SDK/SensorLayer/SensorDataView.hpp"
#include "SDK/Messages/SensorLayerMessages.hpp"

#include <cstdio>

#include "Service.hpp"

#define LOG_MODULE_PRX      "Logger"
#define LOG_MODULE_LEVEL    LOG_LEVEL_DEBUG
#include "SDK/UnaLogger/Logger.h"

Service::Service(SDK::Kernel& kernel)
    : mKernel(SDK::KernelProviderService::GetInstance().getKernel())
    , mSensorWristMotion(SDK::Sensor::Type::WRIST_MOTION, 0, 0)
    , mSensorMotionDetect(SDK::Sensor::Type::MOTION_DETECT, 0, 0)
    , mSensorActivityRecognition(SDK::Sensor::Type::ACTIVITY_RECOGNITION, 0, 0)
    , mSensorHeartRate(SDK::Sensor::Type::HEART_RATE, 0, 0)
    , mSensorBattery(SDK::Sensor::Type::BATTERY_LEVEL, 0, 0)
    , mPendingRows(0)
{
    (void)kernel;
}

void Service::openLog()
{
    mKernel.fs.mkdir(LOG_DIR);

    mFile = mKernel.fs.file(LOG_PATH);
    if (!mFile) {
        LOG_ERROR("could not create file object for %s\n", LOG_PATH);
        return;
    }

    // Each boot starts a fresh session: a run that spans a reboot cannot be
    // stitched together anyway, since uptime restarts with it.
    if (!mFile->open(true, true)) {
        LOG_ERROR("could not open %s for writing\n", LOG_PATH);
        mFile.reset();
        return;
    }

    const char* header = "uptime_ms,sensor,a,b\n";
    size_t written = 0;
    mFile->write(header, __builtin_strlen(header), written);
}

void Service::appendRow(const char* sensor, uint32_t timeMs, float a, float b)
{
    if (!mFile) {
        return;
    }

    char row[64];
    const int len = snprintf(row, sizeof(row), "%lu,%s,%.2f,%.2f\n",
                             static_cast<unsigned long>(timeMs), sensor, a, b);
    if (len <= 0) {
        return;
    }

    size_t written = 0;
    mFile->write(row, static_cast<size_t>(len), written);

    if (++mPendingRows >= FLUSH_THRESHOLD) {
        flush();
    }
}

void Service::flush()
{
    if (!mFile || mPendingRows == 0) {
        return;
    }

    // close/reopen is the only durability barrier IFile exposes -- there is no
    // sync() -- and reopening without override appends.
    mFile->close();
    mFile->open(true, false);
    mPendingRows = 0;
}

void Service::connectSensors()
{
    mSensorWristMotion.connect();
    mSensorMotionDetect.connect();
    mSensorActivityRecognition.connect();
    mSensorHeartRate.connect();
    mSensorBattery.connect();
}

void Service::disconnectSensors()
{
    mSensorWristMotion.disconnect();
    mSensorMotionDetect.disconnect();
    mSensorActivityRecognition.disconnect();
    mSensorHeartRate.disconnect();
    mSensorBattery.disconnect();
}

void Service::onSensorData(uint16_t handle, SDK::Sensor::DataBatch& data)
{
    const uint32_t now = mKernel.sys.getTimeMs();
    SDK::Sensor::DataView view(data[0]);

    if (mSensorWristMotion.matchesDriver(handle)) {
        SDK::SensorDataParser::WristMotion parser(view);
        if (parser.isWristMotion()) {
            LOG_INFO("wrist motion @%lu\n", static_cast<unsigned long>(now));
            appendRow("wrist", now, 1.0f, 0.0f);
        }
    } else if (mSensorMotionDetect.matchesDriver(handle)) {
        SDK::SensorDataParser::MotionDetect parser(view);
        appendRow("motion", now, static_cast<float>(parser.getID()), 0.0f);
    } else if (mSensorActivityRecognition.matchesDriver(handle)) {
        SDK::SensorDataParser::ActivityRecognition parser(view);
        appendRow("activity", now, static_cast<float>(parser.getID()),
                  static_cast<float>(parser.getConfidence()));
    } else if (mSensorHeartRate.matchesDriver(handle)) {
        SDK::SensorDataParser::HeartRate parser(view);
        appendRow("hr", now, parser.getBpm(), parser.getTrustLevel());
    } else if (mSensorBattery.matchesDriver(handle)) {
        SDK::SensorDataParser::BatteryLevel parser(view);
        appendRow("battery", now, parser.getCharge(), 0.0f);
    }
}

void Service::run()
{
    LOG_INFO("logger service started\n");

    openLog();
    connectSensors();

    while (true) {
        SDK::MessageBase* msg;
        if (!mKernel.comm.getMessage(msg, 1000)) {
            continue;
        }

        switch (msg->getType()) {
            case SDK::MessageType::COMMAND_APP_STOP:
                LOG_INFO("stopping\n");
                disconnectSensors();
                flush();
                if (mFile) {
                    mFile->close();
                }
                mKernel.comm.releaseMessage(msg);
                return;

            case SDK::MessageType::EVENT_SENSOR_LAYER_DATA: {
                auto event = static_cast<SDK::Message::Sensor::EventData*>(msg);
                SDK::Sensor::DataBatch data(event->data, event->count, event->stride);
                onSensorData(event->handle, data);
                break;
            }

            default:
                break;
        }

        mKernel.comm.releaseMessage(msg);
    }
}
