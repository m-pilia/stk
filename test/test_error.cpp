#include "catch.hpp"

#include <stk/common/error.h>
#include <stk/common/log.h>

namespace
{
    struct LogData
    {
        int last_level;
        std::string last_msg;
    };

    void log_callback(void* user_data, stk::LogLevel level, const char* msg)
    {
        LogData* data = static_cast<LogData*>(user_data);
        data->last_level = level;
        data->last_msg = msg;
    }
}

TEST_CASE("error", "[error] [logging]")
{
    stk::log_init();
    
    LogData data = { -1, "" };
    stk::log_add_callback(log_callback, &data, stk::Fatal);



    stk::log_remove_callback(log_callback, &data);
    stk::log_shutdown();
}