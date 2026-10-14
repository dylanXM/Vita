# 原画风宠物与环境联动

## 已确认范围

2026-10-14 用户认可毛茸茸的立体卡通动作设计稿，并要求与环境联动。取消程序绘制的积木像素宠物；保留四季昼夜小屋和全屏展示。覆盖仓库现有六个默认品种与桌面悬浮宠物。

## 实现

- 六个品种各有一张 4×6 动作图与一张同尺寸黑白透明遮罩，正式文件位于 app/assets/ai_pets/motion_v3/。原有照片、旧动作图和 Admin 配置没有覆盖。
- 动作图第一至第六行分别为待机、步态、低头吃喝、坐下、蜷睡、抚摸回应，每行四帧；反向播放起身阶段后再进入下一姿态，不叠加两个完整宠物。
- ImageGen 返回的彩色图仍有底色。载入时用对应轮廓遮罩的红通道计算彩色图的预乘 RGBA，生成真正的透明宠物图；逐帧只绘制这张彩色透明图，不直接绘制遮罩，也不使用逐帧 dstIn 混合。遮罩同样由 ImageGen 制作。
- 每次载入从遮罩计算各帧脚底基线，保持实际落地位置，坐下／蜷睡不会被单独放大成站立高度；屏幕、家具、影子、宠物共用固定场景坐标。
- 食盆、水盆、小床、地毯、门可触发原有照料操作。走到物件旁后才展示对应动作。离床经开阔地板；起身时先等待动作过渡，不拖着蜷睡姿态移动。
- 喂食／喝水的前端动作时长为六秒，散步十秒、坐下七秒、休息十一秒，包含移动及过渡。服务端价格、数值与幂等规则保持原样。
- 昼夜背景变化同步调整宠物光照与接触阴影，喝水有局部水面波纹。抚摸在当前位置反馈，不先赶回地毯。
- 桌面宠物使用同一正式素材、连续时钟和拖动响应；后台、减少动态效果时停止动画。
- 未配置本次正式图的自定义宠物保持自身原有形象，不替换成默认猫／狗。

## 检查与边界

已人工逐张查看六个品种的动作图及遮罩，检查资源声明、原接口回调、状态中断、异步图片载入失效保护、页面退出和生命周期处理。源码搜索确认小屋与桌面入口已无 PixelPet 引用。

遵照用户规范，没有执行 test、check、analyze、build，没有进行 Git 操作。未取得 Flutter 编译或设备验证结果；不能据此宣称设备动作表现已通过。

最快验证：停止现有 Flutter 进程，根目录 make app-run 重新打包新增资源。打开 Mochi，依次喂食、喝水、休息、散步、坐下、抚摸，检查嘴对碗、身体位于床垫上、四肢步态、起身后再走、没有彩色方形底图和重复家具；换其余五个品种。返回聊天页拖动悬浮宠物，打开键盘、切后台并恢复；开启减少动态效果再检查。

仅 App 修改，无 Backend、Admin、Webapp API 或数据库变更，兼容原上线顺序。

## ImageGen 提示词

使用内置 ImageGen，每个品种单独以其原形象作参考。动作图提示词如下：

+Create ONE production animation sprite atlas for the exact pet in the reference. Preserve the ORIGINAL soft fluffy 3D animated-film illustration style, same fur, colors, face and anatomy. NOT pixel art. TRANSPARENT RGBA background throughout; no painted backgrounds, no checkerboard texture, no shadows, no labels, no outlines, no panel lines, no text. Portrait canvas ratio 2:3. EXACTLY FOUR columns and SIX rows = 24 square cells, mathematically equally spaced grid. ONE complete pet per cell, no repeated stray limbs and no silhouettes touching adjacent cells. Within EVERY square cell, reserve 12% transparent padding on all sides; keep all grounded paws at 86% of cell height, character center at 50% cell width. Same animal scale and camera in all cells, no zoom. Body must stay fully within its own cell. Fur detailed and beautiful but legible at small game size.
ROW 1 left to right: relaxed standing 3/4 front view with head towards LEFT, normal eyes; same stance slight breathing with tail relaxed; SAME stance eyes blinking closed; SAME stance eyes reopening. A subtle 4-frame seamless idle.
ROW 2: four consecutive walking cycle frames, side three-quarter view facing LEFT; diagonal paws alternate planted and lifted, continuous coherent gait, head and body stay at same level and scale; no ghost traces, no motion blur.
ROW 3: four successive lowering-head stages for feeding/drinking, LEFT-facing three-quarter view: standing with head up; head halfway down; muzzle down close to floor and eyes content; same muzzle-down pose tiny chewing/licking. NO bowl, NO food, NO water, NO furniture. Pet-only sprites.
ROW 4: four successive sit-down stages: standing; hindquarters halfway lowering; seated with paws tucked; same seated calm pose. Feet share the same floor baseline.
ROW 5: four successive lie-down stages: seated lower; front elbows lowering and chest near floor; curl body and wrap tail; fully curled asleep, closed eyes, no bed or cushion. Same floor baseline.
ROW 6: four successive gentle petting reaction stages: relaxed standing; tilt head with delighted soft eyes; eyes closed happily and ears relaxed; reopen eyes and return to original standing. No hand, no hearts, no accessories.
Keep expression sweet and polished. Each row is a coherent animation of the SAME character, not independently redesigned animals. Camera perspective, face and texture consistent with reference. Every cell is a clean transparent cutout.

对应遮罩提示：Create an exact ALPHA MATTE / segmentation mask of this supplied 1024x1536 animation atlas. Preserve exact pixel positions of all 24 pets, four columns by six rows. Entire pet silhouette pure white, all background and shadows pure black. No eyes, mouth or inner details in the matte; only narrow antialiased grey fur fringes. Same canvas, no moving, resizing, cropping, new grid or labels.
