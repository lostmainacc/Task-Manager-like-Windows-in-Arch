# Task-Manager-like-Windows-in-Arch

Virus Total: https://www.virustotal.com/gui/file/b8f021c464df01dffa8b5e18bccee110aaffcbd07681718990823ad8ccf0906c?nocache=1

**Guide to download this Task Manager:**

```
sudo pacman -Syu

sudo pacman -S python pyside6 python-psutil

python3 -c "import PySide6, psutil; print('All modules imported successfully')"

chmod +x install_system_task_manager_fixed.sh

sudo ./install_system_task_manager_fixed.sh

(Uninstall) sudo ./install_system_task_manager_fixed.sh --uninstall
