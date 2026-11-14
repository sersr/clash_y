# The JNI function names in libclash.so are derived from the class and native
# method names. Keep them even when the app is minified.
-keep class io.aote.vpnService.** { *; }

# Rhino and SnakeYAML reference JavaBeans APIs that are not available on
# Android. The profile script path serializes plain maps and never uses them.
-dontwarn java.beans.BeanDescriptor
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.FeatureDescriptor
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor