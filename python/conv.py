import numpy as np

def conv2d(image, kernel):
    """
    对二维矩阵 image 进行二维卷积运算（无填充，步幅为 1）
    
    参数：
      image：输入矩阵，形状为 (H, W)
      kernel：卷积核，形状为 (kH, kW)
    
    返回：
      卷积输出矩阵，形状为 (H - kH + 1, W - kW + 1)
    """
    H, W = image.shape       # 输入矩阵的高和宽
    kH, kW = kernel.shape     # 卷积核的高和宽
    
    # 计算输出矩阵的尺寸
    outH = H - kH + 1
    outW = W - kW + 1
    output = np.zeros((outH, outW))
    
    # 进行卷积操作
    for i in range(outH):
        for j in range(outW):
            # 取出对应的区域，然后与卷积核做对应元素乘法再求和
            region = image[i:i+kH, j:j+kW]
            output[i, j] = np.sum(region * kernel)
    return output

# 自定义 14×14 的输入矩阵
# 这里我们构造一个从 1 到 196 的顺序数矩阵，便于观察变化
input_matrix = np.arange(1, 14*14 + 1).reshape(14, 14)

# 自定义一个 3×3 的卷积核
# 这里以一个简单的拉普拉斯算子（边缘检测核）为例
kernel = np.array([
    [0,  1, 0],
    [1, -4, 1],
    [0,  1, 0]
])

# 打印输入矩阵
print("输入矩阵 (14×14):")
print(input_matrix)

# 打印卷积核
print("\n卷积核 (3×3):")
print(kernel)

# 计算卷积结果
result = conv2d(input_matrix, kernel)

# 打印卷积后的输出矩阵，大小为 (12×12)
print("\n卷积结果 (12×12):")
print(result)
