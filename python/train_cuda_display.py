import torch
import torch.nn.functional as F
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms

from torch.ao.quantization import QuantStub, DeQuantStub
from torch.ao.quantization import prepare, convert
from torch.ao.quantization import get_default_qconfig  # 量化配置
from torch.ao.quantization import QConfig
from torch.ao.quantization.observer import MinMaxObserver


def print_weight_info(conv_layer, layer_name="Conv"):
    w = conv_layer.weight()
    b = conv_layer.bias
    scheme = w.qscheme()
    print(f"\n>>> {layer_name} 权值相关信息:")
    print("  量化模式(qscheme):", scheme)

    if scheme == torch.per_tensor_affine:
        print("  weight scale:", w.q_scale())
        print("  weight zero_point:", w.q_zero_point())
    elif scheme == torch.per_channel_affine:
        print("  weight scales:", w.q_per_channel_scales())
        print("  weight zero_points:", w.q_per_channel_zero_points())

    print("  weight int_repr:", w.int_repr().flatten())
    # print("  weight int_repr (前10个元素):", w.int_repr().flatten()[:10])
    print("  bias (float):", b)


def debug_inference(quant_model, x_fp32):
    """
    对单个 batch 做一次前向传播，打印每一步的量化参数、权重和中间输出等信息。
    适用于已经 convert() 完成的 quant_model。
    """
    print("===== Debug Inference Start =====")
    
    # [1] 打印原始输入 (FP32)
    print(">>> 原始输入图像 (FP32) shape:", x_fp32.shape)
    print(x_fp32)
    
    # [2] 量化输入 (QuantStub)
    x_quant = quant_model.quant(x_fp32)
    print("\n>>> 输入量化 (QuantStub)")
    print("QuantStub scale:", quant_model.quant.scale.item())
    print("QuantStub zero_point:", quant_model.quant.zero_point.item())
    print("Quantized input int_repr:\n", x_quant.int_repr())
    # print("Quantized input dequant (查看反量化值):\n", x_quant.dequantize())

    # [3] 【与原 forward 保持一致】先做第一次 MaxPool2d
    x_pool0 = F.max_pool2d(x_quant, 2)
    print("\n>>> 第一次 MaxPool2d 后 int_repr shape:", x_pool0.int_repr().shape)

    # [4] conv1 + ReLU + MaxPool
    print_weight_info(quant_model.conv1, "Conv1")
    print("Bias value:", quant_model.conv1.bias())
    out1 = quant_model.conv1(x_pool0)
    print("\n>>> Conv1 输出:")
    print("  out1 scale:     ", out1.q_scale())
    print("  out1 zero_point:", out1.q_zero_point())
    print("  out1 int_repr shape:", out1.int_repr().shape)
    print("  out1 int_repr (前10个元素):\n", out1.int_repr().flatten()[:10])
    
    out1_relu = F.relu(out1)
    print(">>> ReLU 后 int_repr (前10个元素):\n", out1_relu.int_repr().flatten()[:10])
    
    out1_pool = F.max_pool2d(out1_relu, 2)
    print(">>> MaxPool2d 后 int_repr shape:", out1_pool.int_repr().shape)
    
    # [5] conv2 + ReLU + MaxPool
    print_weight_info(quant_model.conv2, "Conv2")
    print("Bias value:", quant_model.conv2.bias())
    out2 = quant_model.conv2(out1_pool)
    print("\n>>> Conv2 输出:")
    print("  out2 scale:     ", out2.q_scale())
    print("  out2 zero_point:", out2.q_zero_point())
    print("  out2 int_repr shape:", out2.int_repr().shape)
    print("  out2 int_repr (前10个元素):\n", out2.int_repr().flatten()[:10])
    
    out2_relu = F.relu(out2)
    out2_pool = F.max_pool2d(out2_relu, 2)
    print(">>> ReLU+MaxPool2d 后 shape:", out2_pool.int_repr().shape)

    # [6] Flatten
    #   如果你的原网络是 conv2 -> pool => (5,2,2)，那就要 reshape 成 (batch_size, 5*2*2=20)
    out3 = out2_pool.reshape(-1, 5 * 2 * 2)
    print("\n>>> Flatten 后 shape:", out3.shape)
    print("  out3 int_repr (前10个元素):\n", out3.int_repr().flatten()[:10])

    # [7] fc1 + ReLU
    print_weight_info(quant_model.fc1, "FC1")
    print("Bias value:", quant_model.fc1.bias())
    out_fc1 = quant_model.fc1(out3)
    print("\n>>> FC1 输出:")
    print("  out_fc1 scale:     ", out_fc1.q_scale())
    print("  out_fc1 zero_point:", out_fc1.q_zero_point())
    print("  out_fc1 int_repr:", out_fc1.int_repr())
    
    out_fc1_relu = F.relu(out_fc1)

    # [8] fc2 (最后输出)
    print_weight_info(quant_model.fc2, "FC2")
    print("Bias value:", quant_model.fc2.bias())
    out_fc2 = quant_model.fc2(out_fc1_relu)
    print("\n>>> FC2 输出 (Logits):")
    print("  out_fc2 scale:     ", out_fc2.q_scale())
    print("  out_fc2 zero_point:", out_fc2.q_zero_point())
    print("  out_fc2 int_repr:", out_fc2.int_repr())
    
    # [9] 最终 dequant (可选)
    out_dequant = quant_model.dequant(out_fc2)
    print("\n>>> 最终输出 (反量化后) => logits:")
    print(out_dequant)
    print("===== Debug Inference End =====")

    return out_dequant



device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("Using device:", device)

transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Normalize((0.5,), (0.5,))
])

train_dataset = datasets.MNIST(root='./mnist', train=True, transform=transform, download=False)
test_dataset = datasets.MNIST(root='./mnist', train=False, transform=transform, download=False)

train_loader = torch.utils.data.DataLoader(dataset=train_dataset, batch_size=64, shuffle=True)
test_loader = torch.utils.data.DataLoader(dataset=test_dataset, batch_size=64, shuffle=False)

class SimpleCNN(nn.Module):
    def __init__(self):
        super(SimpleCNN, self).__init__()
        self.conv1 = nn.Conv2d(1, 5, kernel_size=3, stride=1, padding=0)
        self.conv2 = nn.Conv2d(5, 5, kernel_size=3, stride=1, padding=0)
        self.fc1 = nn.Linear(5 * 2 * 2, 10)
        self.fc2 = nn.Linear(10, 10)

    def forward(self, x):
        x = F.max_pool2d(x, 2)
        x = F.relu(self.conv1(x))
        x = F.max_pool2d(x, 2)
        x = F.relu(self.conv2(x))
        x = F.max_pool2d(x, 2)
        x = x.view(-1, 5 * 2 * 2)
        x = F.relu(self.fc1(x))
        x = self.fc2(x)
        return x

model = SimpleCNN().to(device)

criterion = nn.CrossEntropyLoss()
optimizer = optim.SGD(model.parameters(), lr=0.01, momentum=0.9)
num_epochs = 20

model.train()

for epoch in range(num_epochs):
    total_loss = 0.0
    correct = 0
    total = 0

    for images, labels in train_loader:
        images, labels = images.to(device), labels.to(device)

        # 前向传播
        outputs = model(images)
        loss = criterion(outputs, labels)

        # 反向传播和更新
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

        # 记录损失
        total_loss += loss.item()

        # 计算训练准确率
        _, predicted = torch.max(outputs, 1)
        correct += (predicted == labels).sum().item()
        total += labels.size(0)

    avg_loss = total_loss / len(train_loader)
    train_accuracy = 100.0 * correct / total

    print(f"Epoch [{epoch+1}/{num_epochs}], Loss: {avg_loss:.4f}, "
          f"Train Accuracy: {train_accuracy:.2f}%")

model.eval()

def evaluate_model(model, data_loader, device):
    correct = 0
    total = 0
    with torch.no_grad():
        for images, labels in data_loader:
            images, labels = images.to(device), labels.to(device)
            outputs = model(images)
            _, predicted = torch.max(outputs, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()
    return 100.0 * correct / total

accuracy_fp32 = evaluate_model(model, test_loader, device)
print(f"FP32 Model Test Accuracy: {accuracy_fp32:.2f}%")


class QuantizableSimpleCNN(nn.Module):
    def __init__(self):
        super(QuantizableSimpleCNN, self).__init__()
        self.quant = QuantStub()
        self.conv1 = nn.Conv2d(1, 5, kernel_size=3, stride=1, padding=0)
        self.conv2 = nn.Conv2d(5, 5, kernel_size=3, stride=1, padding=0)
        self.fc1 = nn.Linear(5 * 2 * 2, 10)
        self.fc2 = nn.Linear(10, 10)
        self.dequant = DeQuantStub()

    def forward(self, x):
        x = self.quant(x)
        x = F.max_pool2d(x, 2)
        x = F.relu(self.conv1(x))
        x = F.max_pool2d(x, 2)
        x = F.relu(self.conv2(x))
        x = F.max_pool2d(x, 2)
        x = x.reshape(-1, 5 * 2 * 2)
        x = F.relu(self.fc1(x))
        x = self.fc2(x)
        x = self.dequant(x)
        return x


# 1) 创建可量化模型，并加载训练后权重
quant_model = QuantizableSimpleCNN()
quant_model.load_state_dict(model.state_dict())  # 拷贝已经训练好的权重
quant_model.to('cpu')  # 静态量化一般在 CPU 上进行
quant_model.eval()

# 2) 设置 qconfig
quant_model.qconfig = get_default_qconfig('fbgemm')

# 定义一个 custom_qconfig，其中激活和权重都采用 per-tensor 量化方式
custom_qconfig = QConfig(
    activation=MinMaxObserver.with_args(dtype=torch.quint8, qscheme=torch.per_tensor_affine),
    weight=MinMaxObserver.with_args(dtype=torch.qint8, qscheme=torch.per_tensor_affine)
)

# 将模型的 qconfig 设为自定义的 QConfig
quant_model.qconfig = custom_qconfig

# 3) prepare: 插入 Observer，准备收集激活分布信息
prepare(quant_model, inplace=True)

#  Calibration 
with torch.no_grad():
    for i, (images, labels) in enumerate(train_loader):
        quant_model(images)  # 仅需前向传播，让 Observer 记录统计信息
        if i >= 100:
            break

# 4) convert: 让 PyTorch 替换相应算子为量化版本
convert(quant_model, inplace=True)

# -----------------------------
#  假设你已经执行了:
#     convert(quant_model, inplace=True)
#  并且 quant_model 现在是量化后的模型
# -----------------------------

# 从 test_loader 里取 1 个 batch (这里只取其中一张图)
test_iter = iter(test_loader)
images, labels = next(test_iter)

# 这里只演示 1 张图，防止输出过多
sample_img = images[0:1]   # shape: [1, 1, 28, 28]
sample_label = labels[0:1]

# 在 CPU 上推理
quant_model.eval()
sample_output = debug_inference(quant_model, sample_img)

# 还可以再打印一下最终分类结果:
_, predicted_class = torch.max(sample_output, dim=1)
print("\n推理结果（预测类别）:", predicted_class.item())
print("真实类别:", sample_label.item())
