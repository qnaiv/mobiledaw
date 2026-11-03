#pragma once

#include <cstdio>
#include <functional>
#include <string>
#include <vector>

// 依存なしの小さなテスト枠。TEST(name) で登録し、test_main.cpp が全部流す。
namespace mdaw_test {

struct TestCase {
    std::string name;
    std::function<void()> fn;
};

inline std::vector<TestCase>& registry() {
    static std::vector<TestCase> tests;
    return tests;
}

inline int& failures() {
    static int n = 0;
    return n;
}

struct Registrar {
    Registrar(const char* name, std::function<void()> fn) { registry().push_back({name, std::move(fn)}); }
};

} // namespace mdaw_test

#define MDAW_CONCAT_(a, b) a##b
#define MDAW_CONCAT(a, b) MDAW_CONCAT_(a, b)

#define TEST(name)                                                                       \
    static void name();                                                                  \
    static mdaw_test::Registrar MDAW_CONCAT(name, _registrar)(#name, name);             \
    static void name()

#define CHECK(cond)                                                                      \
    do {                                                                                 \
        if (!(cond)) {                                                                   \
            std::printf("  FAILED: %s (%s:%d)\n", #cond, __FILE__, __LINE__);            \
            ++mdaw_test::failures();                                                     \
        }                                                                                \
    } while (0)
