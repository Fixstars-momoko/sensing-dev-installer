import sys
import os

if os.name == 'nt':
    os.add_dll_directory(sys.argv[1])

import cv2

# if the opencv is built with gstreamer
info = cv2.getBuildInformation()
print(info)
info = info.split('\n')
for line in info:
    if 'GStreamer' in line:
        if 'NO' in line:
            print('This openCV is not built with Gstreamer')
            sys.exit(1)
        elif 'YES' in line:
            sys.exit(0)

sys.exit(1)