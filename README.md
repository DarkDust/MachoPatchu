# MachoPatchu

Tool to patch load commands of Mach-O files.

This small tool is able to replace dynamic library paths in Mach-O binaries. It can be used to work
around an Xcode 16.x bug that writes incorrect library references into the final executable in
certain circumstances.

The Xcode/linker bug (FB15995117) is triggered by these conditions:

* Have deployment target macOS version X.
* Reference a feature/framework only available in macOS version > X.
* Architecture is supported by macOS version X.

For example:

* Minimum deployment target macOS 10.13.
* Use `Network` framework in Swift (available since macOS 10.14, Swift version available since
  macOS 10.15).
* Architecture x86_64. ARM64 would not be affected since it's only available since macOS 11.

In this case, Xcode copies a compatibility version of `libswiftNetwork.dylib` to the app's bundle.
However, the linker is referencing `@rpath/libswiftNetwork.dylib` for the ARM64 architecture,
but it's referencing the path `/usr/lib/swift/libswiftNetwork.dylib` for x86_64. 
This can cause the app to immediately crash on 10.13 and 10.14 since the dynamic linker cannot find
the library at that path, even if you have guarded all relevant code using `@available` and the
library is weakly linked. 

Another example is the use of Swift async/await with a deployment target < macOS 10.15.
Xcode then references `/usr/lib/swift/libswift_Concurrency.dylib` for x86_64 which does not exist.

Using MachoPatchu, you can fix the binary:

```sh
MachoPatchu <path_to_executable> --replace /usr/lib/swift/libswiftNetwork.dylib=@rpath/libswiftNetwork.dylib
```

The code signature gets broken by this operation and the binary needs to be re-signed.
