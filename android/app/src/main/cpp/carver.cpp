#include <jni.h>
#include <android/log.h>
#include <vector>
#include <cstdint>
#include <cstring>
#include <string>

#define LOG_TAG "NativeCarver"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_nowdigiverse_media_1recovery_MainActivity_carveChunk(JNIEnv *env, jobject thiz, jbyteArray chunk, jlong baseOffset) {
    jsize len = env->GetArrayLength(chunk);
    jbyte *buffer = env->GetByteArrayElements(chunk, JNI_FALSE);
    
    // We will return an array of strings in the format "offset,length,mimeType,confidence"
    std::vector<std::string> foundFiles;

    // A very basic independent carving logic for JPEG, PNG, MP4.
    // This scans linearly through the chunk looking for magic bytes.
    // NOTE: This is a from-scratch implementation and does NOT copy PhotoRec code.

    for (jsize i = 0; i < len - 8; ++i) {
        uint8_t b0 = (uint8_t)buffer[i];
        uint8_t b1 = (uint8_t)buffer[i+1];
        uint8_t b2 = (uint8_t)buffer[i+2];
        uint8_t b3 = (uint8_t)buffer[i+3];

        // JPEG: FF D8 FF
        if (b0 == 0xFF && b1 == 0xD8 && b2 == 0xFF) {
            // Found JPEG header. Let's look for EOF (FF D9) within next 5MB
            jsize max_search = std::min(len, i + 5 * 1024 * 1024);
            jsize eof_pos = -1;
            for (jsize j = i + 3; j < max_search - 1; ++j) {
                if ((uint8_t)buffer[j] == 0xFF && (uint8_t)buffer[j+1] == 0xD9) {
                    eof_pos = j + 2;
                    break;
                }
            }

            int confidence = 50; // default confidence
            jsize file_length = 0;
            if (eof_pos != -1) {
                file_length = eof_pos - i;
                confidence = 90; // high confidence since we found EOF
            } else {
                // Approximate 2MB if EOF not found in this chunk
                file_length = 2 * 1024 * 1024; 
            }

            std::string res = std::to_string(baseOffset + i) + "," + std::to_string(file_length) + ",image/jpeg," + std::to_string(confidence);
            foundFiles.push_back(res);
            
            if (eof_pos != -1) {
                i = eof_pos - 1; // skip parsed bytes
            } else {
                i += 1024; // skip ahead to avoid too many false positives
            }
            continue;
        }

        // PNG: 89 50 4E 47
        if (b0 == 0x89 && b1 == 0x50 && b2 == 0x4E && b3 == 0x47) {
            // PNG EOF is IEND chunk: 00 00 00 00 49 45 4E 44 AE 42 60 82
            jsize max_search = std::min(len, i + 5 * 1024 * 1024);
            jsize eof_pos = -1;
            for (jsize j = i + 8; j < max_search - 11; ++j) {
                if ((uint8_t)buffer[j] == 0x49 && (uint8_t)buffer[j+1] == 0x45 && (uint8_t)buffer[j+2] == 0x4E && (uint8_t)buffer[j+3] == 0x44) {
                    eof_pos = j + 8; // include CRC
                    break;
                }
            }

            int confidence = 50;
            jsize file_length = 0;
            if (eof_pos != -1) {
                file_length = eof_pos - i;
                confidence = 90;
            } else {
                file_length = 2 * 1024 * 1024; 
            }

            std::string res = std::to_string(baseOffset + i) + "," + std::to_string(file_length) + ",image/png," + std::to_string(confidence);
            foundFiles.push_back(res);
            
            if (eof_pos != -1) {
                i = eof_pos - 1;
            } else {
                i += 1024;
            }
            continue;
        }

        // MP4: ftyp (at offset 4)
        if (buffer[i+4] == 0x66 && buffer[i+5] == 0x74 && buffer[i+6] == 0x79 && buffer[i+7] == 0x70) {
            // EOF for MP4 is hard to find by simple byte scanning since it's box-based.
            // We'll give it a default 25MB length and 60% confidence for now.
            jsize file_length = 25 * 1024 * 1024;
            std::string res = std::to_string(baseOffset + i) + "," + std::to_string(file_length) + ",video/mp4,60";
            foundFiles.push_back(res);
            i += 1024 * 1024; // skip ahead 1MB for video
            continue;
        }
    }

    env->ReleaseByteArrayElements(chunk, buffer, JNI_ABORT);

    // Convert vector to String array
    jclass stringClass = env->FindClass("java/lang/String");
    jobjectArray strArray = env->NewObjectArray(foundFiles.size(), stringClass, nullptr);
    for (size_t i = 0; i < foundFiles.size(); ++i) {
        env->SetObjectArrayElement(strArray, i, env->NewStringUTF(foundFiles[i].c_str()));
    }

    return strArray;
}
