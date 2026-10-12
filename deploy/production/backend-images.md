# Backend 本地镜像部署

`vita-backend` 流水线默认选择 `uploaded`，不拉取源码、不在服务器编译。
脚本源文件为 `deploy/production/Jenkinsfile.backend`；Jenkins 当前使用内联脚本，
后续修改此文件时也需要同步到任务配置。

## 本地一键构建

启动 Docker Desktop（需提供 Buildx），在仓库根目录执行：

```sh
make be-image
# 可选：指定可追踪的唯一 tag
make be-image IMAGE_TAG=local-20261012-01
```

命令固定构建 `linux/amd64`，Mac ARM 机器也可以使用。构建完整 backend
镜像，包含 server、migrate、ffmpeg 和健康检查；不执行上传或部署。
只生成一个上传文件：`dist/images/backend.tar.gz`（已由现有 dist 忽略规则排除）。
镜像包内包含固定传输标签 `vita/backend:uploaded`，无需额外标签或校验文件。
重复执行命令会在成功导出后原子替换本地压缩包；失败保留上一次完整文件。
可用 `IMAGE_OUTPUT_DIR=/绝对路径` 指定输出目录。

## 上传与部署

1. 通过宝塔文件管理将唯一文件 `backend.tar.gz` 上传到服务器 `/opt/vita/incoming/`。
   这个目录首次使用时需要创建。若已配置 SSH，也可使用：

   ```sh
   scp dist/images/backend.tar.gz <服务器SSH别名>:/opt/vita/incoming/backend.tar.gz
   ```

2. 上传完成后运行 Jenkins `vita-backend`，保持默认 `BUILD_SOURCE=uploaded`。
   不需要填写文件名、IMAGE_TAG 或 IMAGE_SHA256，BRANCH 在此模式下忽略。
3. 流水线从固定路径加载镜像，确认本次包确实包含传输标签并检查 linux/amd64，
   再按 Jenkins 构建编号打部署标签，执行原有备份、迁移、启动及健康检查。
   Docker 导入失败（包括损坏的 gzip/镜像包）会在备份、迁移和替换容器之前终止。
   启动失败使用原镜像回滚容器，数据库不自动回滚，迁移必须保持兼容。

不要在上传未完成时启动任务；部署期间不要覆盖服务器上的压缩包。
部署成功并通过健康检查后，自动删除服务器上的 `/opt/vita/incoming/backend.tar.gz`。
部署失败时保留压缩包，可以直接重试。`docker load` 直接导入镜像，不创建独立解压目录，
因此没有需要清理的解压文件；运行和回滚所需的 Docker 镜像、数据库备份保留。
本地构建产物不受服务器清理影响。
旧格式 `image.tar.gz` 包需要重新通过 `make be-image` 生成。
backend、admin、webapp 仍按当前发布顺序配套上线，app 后续上线；此次不修改 API。

## 保留 GitHub 构建

选择 `BUILD_SOURCE=github` 并填写 `BRANCH`。流水线保留 GitHub 拉取、构建、备份、
迁移及部署能力，取消 Docker CPU/内存配额和 Go 编译并发、内存限制。
旧分支 Dockerfile 中已有的 Go 限制会在临时 Dockerfile 中移除，不改检出的源文件。
仍禁止同一 backend 任务并发部署，以免覆盖容器和回滚镜像。
在 2 CPU / 2 GB 服务器上选择此模式，编译仍会争用服务资源；日常部署使用 uploaded。

## 验证

本次只进行 shell 语法、Makefile dry-run 和脚本静态检查，未构建镜像或上线。
实际验证：执行 `make be-image`，上传产物，以 uploaded 模式运行任务，检查
Checkout 跳过、Prepare image 没有 go build、Backend 健康检查通过，
Cleanup upload 成功且服务器压缩包已删除，再验证 Admin/Webapp。
