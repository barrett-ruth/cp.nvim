#include <iostream>

int main() {
    std::cout << "this will never compile" << std::endl
    // missing semicolon above
    undefined_function();
    return 0
    // missing semicolon again