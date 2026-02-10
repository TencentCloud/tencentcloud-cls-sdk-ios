// LogContent.h
#import <Foundation/Foundation.h>

// 动态判断是否为 Debug 模式（根据编译环境自动定义）
#if !defined(DEBUG)
    // 若未通过 Xcode 配置定义 DEBUG，手动判断
    #ifdef NDEBUG
        // NDEBUG 是 Release 模式的默认宏，此时不定义 DEBUG
    #else
        // 非 Release 模式（即 Debug），强制定义 DEBUG=1
        #define DEBUG 1
    #endif
#endif

// 定义日志宏（仅在 DEBUG 模式下生效）
#ifdef DEBUG
    #define CLSLog(fmt, ...) NSLog((@"[CLS] %s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
    #define CLSLog(fmt, ...)
#endif
