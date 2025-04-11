import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torchvision import datasets, transforms

import copy

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
num_epochs = 100

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

from torch.ao.quantization import QuantStub, DeQuantStub
from torch.ao.quantization import prepare, convert
from torch.ao.quantization import get_default_qconfig  # 量化配置

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

# 3) prepare: 插入 Observer，准备收集激活分布信息
prepare(quant_model, inplace=True)

#  -- Calibration (这里示例只跑了几批数据，也可以全量跑 train_loader 或者部分即可)
#     注意：如果数据集很大，通常只需要部分数据来校准即可
with torch.no_grad():
    for i, (images, labels) in enumerate(train_loader):
        quant_model(images)  # 仅需前向传播，让 Observer 记录统计信息
        if i >= 100:           # 示例：使用 5 个 batch 做校准
            break

# 4) convert: 让 PyTorch 替换相应算子为量化版本
convert(quant_model, inplace=True)

quant_model.eval()

accuracy_int8 = 0.0
with torch.no_grad():
    correct = 0
    total = 0
    for images, labels in test_loader:
        # 模型和权重量化后一般在 CPU 上推理
        outputs = quant_model(images)  
        _, predicted = torch.max(outputs, 1)
        total += labels.size(0)
        correct += (predicted == labels).sum().item()

accuracy_int8 = 100.0 * correct / total

print(f"INT8 Quantized Model Test Accuracy: {accuracy_int8:.2f}%")

# 1) 只保存权重
torch.save(model.state_dict(), "./python/cnn_fp32_weights.pth")
torch.save(quant_model.state_dict(), "./python/cnn_int8_weights.pth")

# 2) 直接保存整个模型 (PyTorch 原生对象)
#    量化模型如果要支持跨平台部署，通常还需要转为 TorchScript 等。
torch.save(model, "./python/cnn_fp32_full.pth")
# torch.save(quant_model, "./python/model_int8_full.pth")
scripted_model = torch.jit.script(quant_model)
torch.jit.save(scripted_model, "./python/cnn_int8_scripted.pt")
