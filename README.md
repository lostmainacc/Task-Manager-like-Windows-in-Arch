# Task-Manager-like-Windows-in-Arch

**Guide to download this Task Manager:**

```
sudo pacman -Syu

sudo pacman -S python pyside6 python-psutil

python3 -c "import PySide6, psutil; print('All modules imported successfully')"

chmod +x install_system_task_manager_fixed.sh

sudo ./install_system_task_manager_fixed.sh

(Uninstall) sudo ./install_system_task_manager.sh --uninstall ```
