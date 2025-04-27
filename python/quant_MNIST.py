# quantize_mnist.py
import argparse
import torch
from torchvision import datasets, transforms

# ----------------- 配置 -----------------
SCALE       = 0.007843137718737125   # QuantStub scale
ZERO_POINT  = 127                    # QuantStub zero_point
# ---------------------------------------

def quantize_fp32_to_uint8(x_fp32, scale=SCALE, zp=ZERO_POINT):
    """
    将 [-1, 1] 区间的浮点张量量化到 uint8.
    返回 torch.uint8 张量
    """
    y = torch.round(x_fp32 / scale) + zp        # affine 量化
    y = torch.clamp(y, 0, 255).to(torch.uint8)  # 截断到 [0,255]
    return y


def main(num_imgs: int, out_prefix: str):
    # 1) 数据集：ToTensor 把灰度 0~1 变成 float32; Normalize 把 [0,1] → [-1,1]
    tfm = transforms.Compose([
        transforms.ToTensor(),                       # => [0,1]
        transforms.Normalize((0.5,), (0.5,)),        # => [-1,1]
    ])
    mnist = datasets.MNIST('./mnist', train=False, download=True, transform=tfm)
    loader = torch.utils.data.DataLoader(mnist, batch_size=num_imgs, shuffle=False)

    # 2) 取前 num_imgs 张
    images_fp32, labels = next(iter(loader))        # images: [B,1,28,28] float32
    images_uint8 = quantize_fp32_to_uint8(images_fp32)

    # 3) 将所有图像像素展平，放到一个大数组里
    big_array = images_uint8.reshape(-1).tolist()   # 共 num_imgs*784 个 uint8

    # 4) 写到文件
    with open(f"./python/{out_prefix}_pixels.txt", "w", encoding="utf-8") as f_pixels:
        f_pixels.write(str(big_array))

    with open(f"./python/{out_prefix}_labels.txt", "w", encoding="utf-8") as f_labels:
        f_labels.write(str(labels.tolist()))

    print(f"Saved {len(big_array)} pixels to {out_prefix}_pixels.txt")
    print(f"Saved {labels.numel()} labels to {out_prefix}_labels.txt")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--num", type=int, default=40,
                        help="保存前 N 张图")
    parser.add_argument("--out", type=str, default="mnist_uint8",
                        help="输出文件前缀 (默认 mnist_uint8)")
    args = parser.parse_args()

    main(args.num, args.out)
