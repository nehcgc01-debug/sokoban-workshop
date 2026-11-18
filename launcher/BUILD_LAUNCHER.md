# 启动器构建

Start_BlindTest.exe 沿用 HostReady v2，本轮未改其逻辑。源码为同目录 HostLauncher.cs；使用 Windows 已有 .NET Framework 4.x 编译器，引用 System.Windows.Forms.dll、System.Drawing.dll，目标 winexe。未签名，不下载安装工具。

原构建使用一个32字节Win32空资源；Base64保存在 empty-win32-resource.base64.txt。构建时先解码到**项目目录外的新临时目录**，然后使用已有 csc.exe：

```text
csc.exe /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll /win32res:<临时目录中的empty.res> /out:<临时目录中的Start_BlindTest.exe> HostLauncher.cs
```

编译器常见位置是 Windows 目录下 Microsoft.NET/Framework64/v4.0.30319/csc.exe。按本机实际安装选择；不存在就停止，不改安全策略。路径含空格时需由所用终端正确引用各路径。此构建步骤本轮未重新执行。

empty.res 是 Win32 编译输入，不是 Godot 资源，不能放进运行项目目录。verify_user_data.gd 核对实际 user:// 后只读取已隔离的记录数。诊断日志和会话均不应提交。
