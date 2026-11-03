#include "test_util.h"

int main() {
    for (const auto& t : mdaw_test::registry()) {
        const int before = mdaw_test::failures();
        std::printf("%s\n", t.name.c_str());
        t.fn();
        std::printf("  %s\n", mdaw_test::failures() == before ? "ok" : "NG");
    }
    std::printf("\n%d failure(s)\n", mdaw_test::failures());
    return mdaw_test::failures() == 0 ? 0 : 1;
}
