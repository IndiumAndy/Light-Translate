# 官方技术资料与证据边界

整理日期：2026-09-17。
只用官方公开API。文档入口与检索摘要支持路线选择；实际Swift签名、平台可用性、权限表现以执行时本机SDK及实测为准。
本文不是用户Mac已验证兼容的证据。部分Apple页面依赖JavaScript，开发代理应通过Xcode文档或官方页面核对完整定义。

## S1 — Apple：按屏幕位置取得AX对象

公开接口 `AXUIElementCopyElementAtPosition`，其位置约定为屏幕左上基准。
```text
https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition
```

## S2 — Apple：位置对应字符范围

`kAXRangeForPositionParameterizedAttribute`。不是每个目标应用/对象都会提供；必须检查支持情况。
```text
https://developer.apple.com/documentation/applicationservices/kaxrangeforpositionparameterizedattribute
```

## S3 — Apple：事件监视

global monitor不修改/阻止原事件；local与global范围不同；handler在主线程运行。
该指南是归档文档，应结合本机API与权限行为使用。
```text
https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html
```

## S4 — Apple：非激活NSPanel

`nonactivatingPanel`不激活所属应用；不等于所有操作都不会改变键盘焦点，因此要单独验收。
```text
https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
```

## S5 — Apple：单帧捕获

ScreenCaptureKit的SCScreenshotManager用于单帧截图；区域、过滤器及系统授权细节由本机核实。
```text
https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
```

## S6 — Apple：图像文字识别

VNRecognizeTextRequest在图像中查找、识别文字。不要把整行框等分来推断单词框。
```text
https://developer.apple.com/documentation/vision/vnrecognizetextrequest
https://developer.apple.com/documentation/vision/recognizing-text-in-images
```

## S7 — DeepSeek：API与模型配置

官方Quick Start当前列有deepseek-flash；使用chat completions适配。
模型/参数会变化，第二阶段执行时重新核对。计划不引用固定价格，不保证延迟。
```text
https://api-docs.deepseek.com/
https://api-docs.deepseek.com/api/create-chat-completion
https://api-docs.deepseek.com/guides/thinking_mode
```

## S8 — Apple：Keychain

Keychain services用于保存小型敏感数据；本项目仅为自己的Key创建独立条目。
```text
https://developer.apple.com/documentation/security/keychain-services
```

## S9 — Apple：外部代理访问Xcode

用户已确认本机MCP连接跑通；执行时发现真实工具和参数，不能仅凭示例猜工具名。
```text
https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode
```

## 设计决策而非官方性能承诺

250ms触发等待、4点稳定半径、300msAX超时、800msOCR频率限制、0.65置信阈值、截图像素上限、缓存容量/TTL、15秒网络超时和四阶段划分，均是本方案提出的初值。
单词/句子准确率、软件兼容率、资源占用和响应速度尚未在用户设备测量。
