# Zed Build Runner - Enhanced Project Execution for Zed Editor

![Zed Logo](https://zed.dev/static/images/zed_logo.png)  
*Supercharge your Zed workflow with one-click project execution*

## 📖 Description
A powerful build system integration for Zed Editor that enables F5 execution for **50+ languages/frameworks** with intelligent dependency handling. Created by **Euclidae, the Ever Dreamer**, a barely passable hopefully developer who got addicted to coderunner on vscode.

## ✨ Features
- 🚀 **One-Click Execution** (F5) for:
  - C/C++ (Clang/GCC)
  - Python (Poetry/Pipenv/Venv)
  - Rust (Cargo/Standalone)
  - Web (React/Vue/TypeScript)
  - Game Engines (SDL/OpenGL/Godot)
  - Data Science (Pandas/TensorFlow)
- 🔍 **Auto-Dependency Detection**
  - SDL2/3, OpenGL, Vulkan
  - Boost, ASIO, FMOD
  - ImGui, Raylib, GLFW
- 🛠 **Smart Build Systems**
  - CMake/Make detection
  - C++ Standard Auto-Detection
  - Sanitizer Support (ASan/UBSan)
- 💻 **Hopefully Cross-Platform**
  - Linux (tested on Fedora 41)

## 🛠 Installation
```bash
# Create config directory if missing
mkdir -p ~/.config/zed

# Install configuration files
cp custom_runfile.sh ~/.config/zed/
cp keymaps.json ~/.config/zed/
```

## 🎮 Usage
1. Open any project file in Zed
2. Press <kbd>F5</kbd> to:
   - 🏗 Build project
   - 🔍 Resolve dependencies
   - 🚀 Execute with appropriate runner
   - 📊 View real-time output in Zed console

## ⚙️ Customization
Modify `custom_runfile.sh` to add:
```bash
# Custom build flags
export CXXFLAGS="-O3 -march=native"
# Enable address sanitizer
export ENABLE_SANITIZER=1
# Set Python version
export PYTHON_VERSION=3.11
```

## 🌐 Supported Languages
| Language       | Features                              | Detection Method               |
|----------------|---------------------------------------|---------------------------------|
| **C/C++**      | SDL/OpenGL/Vulkan/Boost               | CMakeLists.txt, #includes       |
| **Python**     | Poetry/Pipenv/Data Science            | pyproject.toml, requirements.txt|
| **Rust**       | Cargo/Bevy Engine                     | Cargo.toml                      |
| **Web**        | React/Vue/TypeScript                  | package.json, node_modules      |
| **Game Dev**   | Godot/Unity/Unreal Engine             | project.godot, .uproject        |

## 📦 Dependency Management
The script automatically detects and suggests missing dependencies:

## 🤝 Contributing
Modifications welcome! Please:
1. Fork the repository
2. Create feature branch
3. Submit PR with detailed description
4. Maintain BSD-3 Clause license
5. Credit original work

## 📜 License
No idea. Do what you want, man. This stuff ain't nothing to me man. I should be solving real problems and improving, not this.

## 🌟 Credits
**Euclidae, the Ever Dreamer**  
*Visionary of the Zed Build System*  
[![GitHub](https://img.shields.io/badge/GitHub-Euclidae-blue)](https://github.com/euclidae)

```ascii-art
         _nnnn_                 
        dGGGGMMb   
       @p~qp~~qMb  
       M|@||@) M|  
       @,----.JM|   
      JS^\__/  qKL
     dZP        qKRb
    dZP          qKKb
   fZP            SMMb
   HZM            MMMM
   FqM            MMMM
 __| ".        |\dS"qML
 |    `.       | `' \Zq
_)      \.___.,|     .'
\____   )MMMMMP|   .'
     `-'       `--' 
```
