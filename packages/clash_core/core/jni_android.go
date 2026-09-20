//go:build android

package main

/*
#include <jni.h>
#include <stdlib.h>

const char *clash_jni_get_string(JNIEnv *env, jstring value);
void clash_jni_release_string(JNIEnv *env, jstring value, const char *chars);
jstring clash_jni_new_string(JNIEnv *env, const char *value);
*/
import "C"

import "unsafe"

// jniStringResult copies a native error string into a Java string and releases
// the C allocation. A nil C string means success and is returned as Java null.
func jniStringResult(env *C.JNIEnv, message *C.char) C.jstring {
	if message == nil {
		return C.jstring(0)
	}
	result := C.clash_jni_new_string(env, message)
	C.free(unsafe.Pointer(message))
	return result
}

func jniError(env *C.JNIEnv, message string) C.jstring {
	return jniStringResult(env, C.CString(message))
}

//export Java_io_aote_vpnService_ClashCore_start
func Java_io_aote_vpnService_ClashCore_start(env *C.JNIEnv, thiz C.jobject, configDir C.jstring) C.jstring {
	if configDir == C.jstring(0) {
		return jniError(env, "configDir is empty")
	}

	cConfigDir := C.clash_jni_get_string(env, configDir)
	if cConfigDir == nil {
		return jniError(env, "configDir is not valid UTF-8")
	}
	defer C.clash_jni_release_string(env, configDir, cConfigDir)

	return jniStringResult(env, start(cConfigDir))
}

//export Java_io_aote_vpnService_ClashCore_startTun
func Java_io_aote_vpnService_ClashCore_startTun(env *C.JNIEnv, thiz C.jobject, configDir C.jstring, tunFd C.jint) C.jstring {
	if configDir == C.jstring(0) {
		return jniError(env, "configDir is empty")
	}
	if tunFd <= 0 {
		return jniError(env, "tun fd is invalid")
	}

	cConfigDir := C.clash_jni_get_string(env, configDir)
	if cConfigDir == nil {
		return jniError(env, "configDir is not valid UTF-8")
	}
	defer C.clash_jni_release_string(env, configDir, cConfigDir)

	return jniStringResult(env, startTun(cConfigDir, tunFd))
}

//export Java_io_aote_vpnService_ClashCore_stop
func Java_io_aote_vpnService_ClashCore_stop(env *C.JNIEnv, thiz C.jobject) C.jstring {
	return jniStringResult(env, stop())
}
