/*

g++ opencv_test.cpp -o opencv_test  \
-I /opt/sensing-dev/include/opencv4 \
-L /opt/sensing-dev/lib \
-lopencv_core  

*/

#include <exception>
#include <iostream>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>

int main(int argc, char *argv[])
{
    try {
         cv::Mat Image(5,5,CV_8UC1);
    }
    catch(std::exception& e) {
         std::cout << e.what() << std::endl;
         return 1;
    }
    std::cout << "PASSED" << std::endl;
    return 0;
   
}
