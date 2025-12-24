# Makefile for VST3Host Julia library

CC = gcc
CXX = g++
# Build universal binary for both Intel and Apple Silicon
# This allows Julia (arm64) to load the library while still supporting x86_64 plugins via Rosetta
ARCH_FLAGS = -arch x86_64 -arch arm64
CFLAGS = -Wall -Wextra -O2 -fPIC -I. $(ARCH_FLAGS)
CXXFLAGS = -Wall -Wextra -O2 -std=c++17 -fPIC -I. -DRELEASE=1 -DSMTG_CPP17=1 $(ARCH_FLAGS)
LDFLAGS = -shared -ldl -framework CoreFoundation -framework Cocoa $(ARCH_FLAGS)

VST3_SDK_PATH = ../vst3sdk

CXXFLAGS += -I$(VST3_SDK_PATH) \
            -I$(VST3_SDK_PATH)/pluginterfaces \
            -I$(VST3_SDK_PATH)/public.sdk \
            -I$(VST3_SDK_PATH)/public.sdk/source \
            -I$(VST3_SDK_PATH)/base/source

TARGET = libvst3host.dylib

# Source files
SOURCES = vst3_host.cpp vst_iids.cpp

# VST3 SDK source files
VST3_SOURCES = \
	$(VST3_SDK_PATH)/public.sdk/source/vst/hosting/module.cpp \
	$(VST3_SDK_PATH)/public.sdk/source/vst/hosting/plugprovider.cpp \
	$(VST3_SDK_PATH)/public.sdk/source/vst/hosting/hostclasses.cpp \
	$(VST3_SDK_PATH)/public.sdk/source/vst/hosting/processdata.cpp \
	$(VST3_SDK_PATH)/public.sdk/source/vst/hosting/parameterchanges.cpp \
	$(VST3_SDK_PATH)/public.sdk/source/vst/hosting/connectionproxy.cpp \
	$(VST3_SDK_PATH)/public.sdk/source/vst/hosting/eventlist.cpp \
	$(VST3_SDK_PATH)/public.sdk/source/vst/hosting/pluginterfacesupport.cpp \
	$(VST3_SDK_PATH)/public.sdk/source/common/memorystream.cpp \
	$(VST3_SDK_PATH)/public.sdk/source/vst/utility/stringconvert.cpp \
	$(VST3_SDK_PATH)/base/source/fobject.cpp \
	$(VST3_SDK_PATH)/base/source/baseiids.cpp \
	$(VST3_SDK_PATH)/base/source/fstreamer.cpp \
	$(VST3_SDK_PATH)/base/source/fstring.cpp \
	$(VST3_SDK_PATH)/base/source/fbuffer.cpp \
	$(VST3_SDK_PATH)/base/source/fdebug.cpp \
	$(VST3_SDK_PATH)/base/source/updatehandler.cpp \
	$(VST3_SDK_PATH)/base/thread/source/flock.cpp \
	$(VST3_SDK_PATH)/pluginterfaces/base/funknown.cpp \
	$(VST3_SDK_PATH)/pluginterfaces/base/ustring.cpp \
	$(VST3_SDK_PATH)/pluginterfaces/base/coreiids.cpp

# macOS-specific Objective-C++ sources
VST3_SOURCES_MM = \
	$(VST3_SDK_PATH)/public.sdk/source/vst/hosting/module_mac.mm \
	$(VST3_SDK_PATH)/public.sdk/source/common/threadchecker_mac.mm

ALL_SOURCES = $(SOURCES) $(VST3_SOURCES)
ALL_SOURCES_MM = $(VST3_SOURCES_MM)
OBJECTS = $(ALL_SOURCES:.cpp=.o) $(ALL_SOURCES_MM:.mm=.o)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CXX) $(LDFLAGS) $^ -o $@

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.o: %.mm
	$(CXX) $(CXXFLAGS) -fobjc-arc -c $< -o $@

clean:
	rm -f $(OBJECTS) $(TARGET)

.SUFFIXES: .cpp .mm .o
