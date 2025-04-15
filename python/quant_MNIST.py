import torch
import numpy as np
from torchvision import datasets, transforms

# =========== 量化参数 ===========
SCALE = 0.015740342438220978
ZERO_POINT = 64 
INT8_MIN, INT8_MAX = -128, 127

mnist_test = datasets.MNIST(root='./mnist', train=False, download=False,
                            transform=transforms.ToTensor())

NUM_IMAGES = 10
assert NUM_IMAGES <= len(mnist_test)

img_file = open('./python/mnist_imgs_int8.bin', 'wb')
lbl_file = open('./python/mnist_labels.bin', 'wb')

for i in range(NUM_IMAGES):
    img, label = mnist_test[i]  
    # img: Tensor, shape [1,28,28], 值在 [0..1] 浮点
    # label: int, [0..9]

    # 转为 numpy, [28,28], [0..1]->[0..255]
    img_np = img.squeeze(0).numpy() * 255.0

    # ========== 做有符号 int8 量化 ==========
    # quant = round(x / scale) + zero_point
    quant_data = np.round(img_np / SCALE + ZERO_POINT)
    # clamp到[-128..127]
    quant_data = np.clip(quant_data, INT8_MIN, INT8_MAX).astype(np.int8)

    # ========== 写入文件 ==========
    # 1) 标签 (1字节)
    lbl_file.write(label.to_bytes(1, byteorder='little', signed=False))
    # 2) 图像 (28×28 = 784 字节, int8)
    img_file.write(quant_data.tobytes())

img_file.close()
lbl_file.close()

print(f"已写入 {NUM_IMAGES} 张图像。")
