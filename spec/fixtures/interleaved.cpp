#include <iostream>
#include <cstdio>

int main() {
    std::cout << "\033[32mstdout: \033[1mSuccess\033[0m" << std::endl;
    std::cerr << "\033[31mstderr: \033[1mWarning\033[0m" << std::endl;
    std::cout << "plain stdout" << std::endl;
    return 0;
}