import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torchvision import datasets, transforms

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("Using device:", device)

# 1. 数据加载
transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Normalize((0.5,), (0.5,))
])

train_dataset = datasets.MNIST(
    root='./mnist', train=True, transform=transform, download=False
)
test_dataset = datasets.MNIST(
    root='./mnist', train=False, transform=transform, download=False
)

train_loader = torch.utils.data.DataLoader(
    dataset=train_dataset, batch_size=64, shuffle=True
)
test_loader = torch.utils.data.DataLoader(
    dataset=test_dataset, batch_size=64, shuffle=False
)

# 2. 定义一个简单 CNN
class SimpleCNN(nn.Module):
    def __init__(self):
        super(SimpleCNN, self).__init__()
        self.conv1 = nn.Conv2d(1, 5, kernel_size=3, stride=1, padding=0)
        self.conv2 = nn.Conv2d(5, 5, kernel_size=3, stride=1, padding=0)
        self.fc1 = nn.Linear(5 * 2 * 2, 10)

    def forward(self, x):
        x = F.max_pool2d(x, 2)            # => (batch_size,1,14,14)
        x = F.relu(self.conv1(x))        # => (batch_size,5,12,12)
        x = F.max_pool2d(x, 2)           # => (batch_size,5,6,6)
        x = F.relu(self.conv2(x))        # => (batch_size,5,4,4)
        x = F.max_pool2d(x, 2)           # => (batch_size,5,2,2)
        x = x.view(-1, 5 * 2 * 2)        # => (batch_size,20)
        out = self.fc1(x)                # => (batch_size,10), raw logits
        return out

model = SimpleCNN().to(device)

# 3. 定义损失和优化器
criterion = nn.CrossEntropyLoss()
optimizer = optim.SGD(model.parameters(), lr=0.01, momentum=0.9)
num_epochs = 5

# 4. 定义一个简单的量化函数: 截取小数部分+clamp到int8
def quantize_param_to_int8(param):
    # 例如, 截取小数部分(去掉小数而不做四舍五入).
    # 如果你想要更贴近最小误差可以改为: p_int = torch.round(param.data)
    p_int = torch.trunc(param.data)
    # clamp到 int8 范围
    p_int = torch.clamp(p_int, -128, 127)
    return p_int

def quantize_model_parameters(model):
    with torch.no_grad():
        for name, param in model.named_parameters():
            param.data = quantize_param_to_int8(param.data)

# 5. 开始训练
for epoch in range(num_epochs):
    model.train()
    running_loss = 0.0
    correct = 0
    total = 0

    for images, labels in train_loader:
        images, labels = images.to(device), labels.to(device)
        
        # 前向传播
        outputs = model(images)
        loss = criterion(outputs, labels)

        # 反向传播
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

        # ---- 在每次更新之后立刻量化权重 ----
        quantize_model_parameters(model)

        running_loss += loss.item()
        
        # 计算训练准确率
        _, predicted = torch.max(outputs, 1)
        correct += (predicted == labels).sum().item()
        total += labels.size(0)

    train_loss = running_loss / len(train_loader)
    train_acc = 100. * correct / total

    # 验证
    model.eval()
    correct_test = 0
    total_test = 0
    with torch.no_grad():
        for images, labels in test_loader:
            images, labels = images.to(device), labels.to(device)
            outputs = model(images)
            _, predicted = torch.max(outputs, 1)
            correct_test += (predicted == labels).sum().item()
            total_test += labels.size(0)
    test_acc = 100. * correct_test / total_test

    print(f"Epoch [{epoch+1}/{num_epochs}] "
          f"Train Loss: {train_loss:.4f}, "
          f"Train Acc: {train_acc:.2f}%, "
          f"Test Acc: {test_acc:.2f}%")
