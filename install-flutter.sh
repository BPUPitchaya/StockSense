#!/bin/bash

# Download and install Flutter
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:$PWD/flutter/bin"
flutter doctor
