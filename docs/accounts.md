# 账号与外观

## 当前支持

| 功能 | 离线账号 | 微软账号 | 第三方认证账号 |
| --- | --- | --- | --- |
| 添加、切换、移除账号 | 支持 | 支持 | 支持 |
| 重新登录、刷新登录 | 无需登录 | 支持 | 支持 |
| 注销远端会话并移除 | 不适用 | 移除本机凭据 | 支持 invalidate |
| 应用皮肤 | 本地 PNG，下次启动生效 | 上传至 Minecraft 服务 | 按服务端 uploadableTextures 权限上传 |
| 应用披风 | 本地 PNG，下次启动生效 | 切换账号已拥有的披风 | 按服务端权限上传 |
| 恢复默认皮肤、移除披风 | 支持 | 支持 | 按服务端权限 |
| 立体预览、旋转、外层开关 | 支持 | 支持 | 支持 |
| 皮肤收藏、重命名、导出 PNG | 支持 | 支持 | 支持 |

第三方认证支持 Yggdrasil / authlib-injector、ALI 地址发现和多角色选择。添加界面有 LittleSkin 快捷入口，仍会请求并验证服务器元数据。

## 离线外观如何进入游戏

应用的皮肤和披风保存在 Ruri 数据目录 `appearance` 下，和皮肤库收藏相互独立。启动器复制本次选用的外观到启动计划，经标准输入管道传递给 `ruri-monitor`。监护进程在随机本地端口建立只监听 `127.0.0.1` 的纹理服务，为角色资料提供临时 RSA 签名，并在 Java 主类之前添加 authlib-injector 参数。

服务的生命周期属于游戏监护进程。关闭启动器窗口不会关闭它；游戏结束、启动失败或停止请求完成后释放服务。更换账号、删除收藏、修改当前外观不会改变已经启动的游戏所使用的副本。

- 离线角色 UUID 保持原值，不因换皮肤改变存档身份。
- 首次使用需要下载经过 SHA-256 校验的 authlib-injector，之后可以复用有效缓存。
- 64 × 32 旧版皮肤保留经典手臂；高清原图保留在收藏中，游戏获得标准尺寸副本。
- 支持仅设置披风而不设置皮肤；22 × 17 披风转换为标准 64 × 32 画布。
- 本地外观不等于向其他玩家发布外观。其他客户端需要对应的服务器皮肤支持或皮肤模组。

## 登录和失败恢复

同一账号的登录刷新、外观请求和启动认证串行执行，避免刷新令牌互相覆盖；不同账号互不等待。外观 API 返回 401 时刷新凭据并重试一次，重复失败留给重新登录处理。取消排队操作不会锁住账号。

重新登录核对角色身份，更新凭据不会把账号切回当前账号。离线账号保存成功后才完成添加；移除账号先提交状态，再清理凭据和外观。第三方账号密码不会持久化，登录令牌保存在钥匙串。

下载皮肤及读取外置服务器响应时，接收过程中就限制数据大小。纹理请求不携带登录令牌或 Cookie；纹理 CDN 的 HTTPS 重定向可以包含签名查询参数。损坏的收藏会单独列为读取问题，不影响其他收藏或新皮肤导入，也不会自动删除原文件。

## 验证记录（2026-09-14）

以下 10 个测试套件共 35 项通过：`AuthenticationTests`、`ExternalAuthenticationTests`、`AccountAppearanceTests`、`SkinLibraryTests`、`OfflineSkinTests`、`AccountOperationGateTests`、`GameSessionTests`、`MonitorLifecycleTests`、`MonitorOwnershipTests`、`StateStoreTests`。最后一次网络读取清理调整后，相关 11 项测试再次通过。

覆盖签名验证、纹理下载、皮肤/披风权限、仅披风模式、尺寸转换、收藏持久化、损坏数据隔离、账号身份匹配、排队取消、监护进程独立存活、退出清理及状态并发保存。

另外通过实际 `ruri-monitor` 启动 Java 25，分别加载 Mojang Authlib **3.3.39、7.0.72、10.0.76** 与 authlib-injector **1.2.8**。三个版本均成功取得签名角色资料、解析皮肤及披风、识别 slim 模型、下载 PNG，并正常退出。该验证使用独立测试目录和虚构离线角色，不使用真实登录凭据或世界存档。

微软真实交互登录、各第三方站点的权限策略，以及多人服务器对皮肤的处理仍取决于对应服务；网络测试使用隔离响应覆盖协议分支，不代表对所有站点和服务器做过实测。

参考：HMCL 的 OfflineAccount / YggdrasilServer / Skin、[authlib-injector 技术规范](https://yushijinhun.github.io/authlib-injector/en/yggdrasil-server-technical-specification.html)、[LittleSkin 外置登录文档](https://manual.littlesk.in/yggdrasil/)。实现为 Swift 原生代码，未复制 HMCL Java 实现。
