# ImageGen 背景资产

正式素材位于 app/assets/ai_pets/cottage_v2/，八张均为 1024×1536。已逐张目视确认，家具布局一致。宠物由 Canvas 像素骨骼绘制，不烘焙进背景。

春日参考提示词：

Create ONE production game background, portrait 2:3, full-bleed. Front-facing interior of a tiny cozy pet cottage, exquisite warm pixel art, crisp deliberate pixel clusters, limited harmonious cream, honey wood, sage green and peach palette, gentle daytime spring light. Straight-on camera with a small amount of visible floor depth, no isometric view. Back wall in upper 55%, roomy unobstructed wooden floor in lower 45%. Large centered window upper third overlooking blossoming trees and fresh spring garden. Pet-sized food bowl at floor x22% y77%, water bowl at x36% y77%; soft round rug around x52% y82%; low cozy cushion pet bed at x78% y72%; closed cottage door at x12% y54%. A short bookshelf, plant and warm reading lamp along back wall. All props sized for cats and dogs and grounded with consistent contact shadows. Warm, safe, lived-in, airy, charming 1990s handheld pixel game aesthetic with modern polished color design. No animals, no humans, no text, no UI, no watermark, no border. This is the reference layout for eight seasonal day/night variations; all furniture must have clear fixed positions.

其余七张逐张使用春日成图作参考，要求严格保持相机、家具、窗口、地板和接触阴影位置，只修改室内光照及窗外季节：春夜月光与花树，夏日绿树，夏夜蓝色月光与窗外萤火，秋日金红树叶，秋夜暖灯与月光，冬日积雪，冬夜蓝色雪景与暖灯。每张独立生成，无拼图。

实际成图交互锚点采用目视位置，而非提示词中的期望坐标：食盆 (0.145,0.71)、水盆 (0.29,0.71)、小床 (0.84,0.65)、地毯 (0.56,0.84)。场景与宠物共用固定画布缩放，避免屏幕变化造成错位。
