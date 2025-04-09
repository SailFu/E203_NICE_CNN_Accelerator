import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
import torch.quantization as quant
from torchvision import datasets, transforms

# 1. 数据加载与预处理
transform = transforms.Compose([
    transforms.ToTensor(),  
    transforms.Normalize((0.5,), (0.5,))  # 数据归一化到 [-1, 1]
])

train_dataset = datasets.MNIST(root='./mnist', train=True, transform=transform, download=False)
test_dataset = datasets.MNIST(root='./mnist', train=False, transform=transform, download=False)

train_loader = torch.utils.data.DataLoader(dataset=train_dataset, batch_size=64, shuffle=True)
test_loader  = torch.utils.data.DataLoader(dataset=test_dataset, batch_size=64, shuffle=False)


class QuantizedCNN(nn.Module):
    def __init__(self):
        super(QuantizedCNN, self).__init__()
        self.quant   = quant.QuantStub()
        self.conv1   = nn.Conv2d(1, 9, kernel_size=3, stride=1, padding=1)
        self.relu1   = nn.ReLU()
        self.pool1   = nn.MaxPool2d(2)
        self.conv2   = nn.Conv2d(9, 9, kernel_size=3, stride=1, padding=1)
        self.relu2   = nn.ReLU()
        self.pool2   = nn.MaxPool2d(2)
        self.fc1     = nn.Linear(9 * 7 * 7, 10)
        self.relu3   = nn.ReLU()
        self.fc2     = nn.Linear(10, 10)
        self.dequant = quant.DeQuantStub()

    def forward(self, x):
        # 量化输入
        x = self.quant(x)
        x = self.pool1(self.relu1(self.conv1(x)))
        x = self.pool2(self.relu2(self.conv2(x)))
        # 使用 reshape 展平
        x = x.reshape(x.size(0), -1)
        x = self.relu3(self.fc1(x))
        x = self.fc2(x)
        # 反量化输出
        x = self.dequant(x)
        return x


# 创建模型实例
model = QuantizedCNN()

# 定义损失函数与优化器
criterion = nn.CrossEntropyLoss()
optimizer = optim.SGD(model.parameters(), lr=0.01, momentum=0.9)


# 3. 模型训练（每个 epoch 计算训练准确率）
num_epochs = 10
model.train()

for epoch in range(num_epochs):
    train_loss = 0.0
    correct = 0
    total = 0
    for images, labels in train_loader:
        outputs = model(images)
        loss = criterion(outputs, labels)

        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

        train_loss += loss.item()

        # 计算当前批次的准确率
        _, predicted = torch.max(outputs.data, 1)
        total += labels.size(0)
        correct += (predicted == labels).sum().item()

    avg_loss = train_loss / len(train_loader)
    accuracy = 100 * correct / total
    print(f"Epoch [{epoch+1}/{num_epochs}]: Loss: {avg_loss:.4f}, Training Accuracy: {accuracy:.2f}%")


# 4. 测试浮点模型的准确率
model.eval()
correct = 0
total = 0
with torch.no_grad():
    for images, labels in test_loader:
        outputs = model(images)
        _, predicted = torch.max(outputs.data, 1)
        total += labels.size(0)
        correct += (predicted == labels).sum().item()

float_accuracy = 100 * correct / total
print(f"Floating Point Model Test Accuracy: {float_accuracy:.2f}%")


# 5. 静态量化流程（int8 静态量化）
# 设置量化配置，采用 'fbgemm' 后端，适用于 x86 CPU
model.qconfig = quant.get_default_qconfig('fbgemm')

# 对模块进行融合（fusion 仅适用于以 nn.Module 形式定义的子模块）
# 这里将 conv+relu 以及 fc1+relu3 融合以减少量化误差
fuse_modules = [['conv1', 'relu1'], ['conv2', 'relu2'], ['fc1', 'relu3']]
quant.fuse_modules(model, fuse_modules, inplace=True)

# 准备量化：在模型中插入 observer 以便校准激活分布
model_prepared = quant.prepare(model, inplace=False)

# 校准模型（使用部分训练数据作为校准集）
model_prepared.eval()
with torch.no_grad():
    for i, (images, _) in enumerate(train_loader):
        model_prepared(images)
        if i >= 100:  # 仅使用前 10 个批次进行校准
            break

# 转换为量化模型（int8 版）
model_int8 = quant.convert(model_prepared, inplace=False)

# 6. 测试量化模型的准确率
model_int8.eval()
correct = 0
total = 0
with torch.no_grad():
    for images, labels in test_loader:
        outputs = model_int8(images)
        _, predicted = torch.max(outputs.data, 1)
        total += labels.size(0)
        correct += (predicted == labels).sum().item()

int8_accuracy = 100 * correct / total
print(f"INT8 Quantized Model Test Accuracy: {int8_accuracy:.2f}%")

torch.save(model_int8.state_dict(),'./python/model_int8.pth')

# # 脚本化量化模型，该过程会将模型转换为 TorchScript 格式，
# # 脚本化的模型包含了完整的前向计算图和量化信息
# scripted_model = torch.jit.script(model_int8)

# # 将脚本化的模型保存到文件
# scripted_model.save("quantized_model_scripted.pt")

print("量化后的模型已保存，并包含量化信息。")

