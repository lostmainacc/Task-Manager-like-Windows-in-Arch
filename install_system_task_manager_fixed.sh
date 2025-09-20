#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="System Task Manager"
APP_DIR="/opt/system_task_manager"
BIN_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/256x256/apps"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root (use sudo)"
        exit 1
    fi
}

# Function to check if package is installed
package_installed() {
    pacman -Qi "$1" >/dev/null 2>&1
}

# Function to check if Python module is installed
python_module_installed() {
    python3 -c "import $1" 2>/dev/null
}

# Function to install dependencies
install_dependencies() {
    print_status "Checking dependencies..."
    
    # Check Python
    if ! command_exists python3; then
        print_status "Installing Python..."
        pacman -S --noconfirm python
    fi

    # Check PySide6
    if ! python_module_installed "PySide6"; then
        print_status "PySide6 not found. Installing..."
        if pacman -Si pyside6 >/dev/null 2>&1; then
            pacman -S --noconfirm pyside6
        else
            print_error "pyside6 package not found in repositories"
            print_error "Please install manually: sudo pacman -S pyside6"
            exit 1
        fi
    fi

    # Check psutil
    if ! python_module_installed "psutil"; then
        print_status "psutil not found. Installing..."
        if pacman -Si python-psutil >/dev/null 2>&1; then
            pacman -S --noconfirm python-psutil
        else
            print_error "python-psutil package not found in repositories"
            print_error "Please install manually: sudo pacman -S python-psutil"
            exit 1
        fi
    fi

    # Verify all dependencies
    if python_module_installed "PySide6" && python_module_installed "psutil"; then
        print_success "All dependencies are installed"
    else
        print_error "Some dependencies are missing"
        print_error "Please install manually: sudo pacman -S pyside6 python-psutil"
        exit 1
    fi
}

# Function to create directories
create_directories() {
    print_status "Creating directory structure..."
    
    mkdir -p "$APP_DIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "$DESKTOP_DIR"
    mkdir -p "$ICON_DIR"
    mkdir -p "/usr/share/icons/hicolor/48x48/apps"
    mkdir -p "/usr/share/icons/hicolor/32x32/apps"
    
    print_success "Directory structure created"
}

# Function to create the main application
create_application() {
    print_status "Creating System Task Manager application..."

    cat > "$APP_DIR/system_task_manager.py" << 'EOF'
#!/usr/bin/env python3
import sys
import psutil
import time
import os
from datetime import datetime
from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                              QHBoxLayout, QTableWidget, QTableWidgetItem, 
                              QPushButton, QLabel, QHeaderView, QTabWidget,
                              QSplitter, QProgressBar, QTreeWidget, QTreeWidgetItem,
                              QMenu, QMessageBox, QLineEdit, QToolBar, QStatusBar)
from PySide6.QtCore import Qt, QTimer, QThread, Signal
from PySide6.QtGui import QIcon, QAction, QPalette, QColor, QFont

class ProcessUpdaterThread(QThread):
    update_signal = Signal(list)
    
    def run(self):
        while True:
            processes = []
            for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info', 'status', 'username', 'create_time']):
                try:
                    mem_info = proc.info['memory_info']
                    memory_mb = mem_info.rss / 1024 / 1024 if mem_info else 0
                    
                    processes.append({
                        'pid': proc.info['pid'],
                        'name': proc.info['name'],
                        'cpu': proc.info['cpu_percent'],
                        'memory_mb': memory_mb,
                        'status': proc.info['status'],
                        'user': proc.info['username'],
                        'create_time': datetime.fromtimestamp(proc.info['create_time']).strftime('%H:%M:%S') if proc.info['create_time'] else 'N/A'
                    })
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                    pass
            
            # Sort by CPU usage (descending)
            processes.sort(key=lambda x: x['cpu'], reverse=True)
            self.update_signal.emit(processes)
            time.sleep(1)

class SystemTaskManager(QMainWindow):
    def __init__(self):
        super().__init__()
        self.init_ui()
        self.process_updater = ProcessUpdaterThread()
        self.process_updater.update_signal.connect(self.update_process_list)
        self.process_updater.start()
        
    def init_ui(self):
        self.setWindowTitle("System Task Manager - Arch Linux")
        self.setGeometry(100, 100, 1200, 800)
        
        # Create toolbar
        toolbar = QToolBar()
        self.addToolBar(toolbar)
        
        # Create status bar
        self.statusBar().showMessage("Ready")
        
        # Central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        
        main_layout = QVBoxLayout(central_widget)
        
        # System info bar
        sys_info_layout = QHBoxLayout()
        
        # CPU usage
        cpu_widget = QWidget()
        cpu_layout = QVBoxLayout(cpu_widget)
        cpu_layout.addWidget(QLabel("CPU Usage"))
        self.cpu_bar = QProgressBar()
        self.cpu_bar.setMaximum(100)
        self.cpu_bar.setTextVisible(True)
        cpu_layout.addWidget(self.cpu_bar)
        self.cpu_label = QLabel("0%")
        cpu_layout.addWidget(self.cpu_label)
        sys_info_layout.addWidget(cpu_widget)
        
        # Memory usage
        mem_widget = QWidget()
        mem_layout = QVBoxLayout(mem_widget)
        mem_layout.addWidget(QLabel("Memory Usage"))
        self.mem_bar = QProgressBar()
        self.mem_bar.setMaximum(100)
        self.mem_bar.setTextVisible(True)
        mem_layout.addWidget(self.mem_bar)
        self.mem_label = QLabel("0%")
        mem_layout.addWidget(self.mem_label)
        sys_info_layout.addWidget(mem_widget)
        
        main_layout.addLayout(sys_info_layout)
        
        # Process table
        self.process_table = QTableWidget()
        self.process_table.setColumnCount(6)
        self.process_table.setHorizontalHeaderLabels(["PID", "Name", "CPU %", "Memory (MB)", "Status", "User"])
        self.process_table.horizontalHeader().setSectionResizeMode(QHeaderView.Interactive)
        self.process_table.setSortingEnabled(True)
        self.process_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.process_table.setContextMenuPolicy(Qt.CustomContextMenu)
        self.process_table.customContextMenuRequested.connect(self.show_context_menu)
        
        # Set column widths
        self.process_table.setColumnWidth(0, 80)   # PID
        self.process_table.setColumnWidth(1, 200)  # Name
        self.process_table.setColumnWidth(2, 80)   # CPU %
        self.process_table.setColumnWidth(3, 100)  # Memory
        self.process_table.setColumnWidth(4, 100)  # Status
        self.process_table.setColumnWidth(5, 120)  # User
        
        main_layout.addWidget(self.process_table)
        
        # Action buttons
        action_layout = QHBoxLayout()
        
        end_task_btn = QPushButton("End Task")
        end_task_btn.clicked.connect(self.end_selected_task)
        action_layout.addWidget(end_task_btn)
        
        end_process_btn = QPushButton("End Process")
        end_process_btn.clicked.connect(self.end_selected_process)
        action_layout.addWidget(end_process_btn)
        
        refresh_btn = QPushButton("Refresh")
        refresh_btn.clicked.connect(self.refresh_processes)
        action_layout.addWidget(refresh_btn)
        
        action_layout.addStretch()
        
        main_layout.addLayout(action_layout)
        
        # System monitor timer
        self.sys_monitor_timer = QTimer()
        self.sys_monitor_timer.timeout.connect(self.update_system_info)
        self.sys_monitor_timer.start(1000)
        
        # Process count label
        self.process_count_label = QLabel("Processes: 0")
        self.statusBar().addPermanentWidget(self.process_count_label)
        
    def update_system_info(self):
        # CPU usage
        cpu_percent = psutil.cpu_percent(interval=0.1)
        self.cpu_bar.setValue(int(cpu_percent))
        self.cpu_bar.setFormat(f"{cpu_percent:.1f}%")
        self.cpu_label.setText(f"{psutil.cpu_count()} cores, {cpu_percent:.1f}% used")
        
        # Memory usage
        mem = psutil.virtual_memory()
        mem_percent = mem.percent
        self.mem_bar.setValue(int(mem_percent))
        self.mem_bar.setFormat(f"{mem_percent:.1f}%")
        self.mem_label.setText(f"{mem.used//1024//1024}MB / {mem.total//1024//1024}MB")
        
    def update_process_list(self, processes):
        self.process_table.setRowCount(len(processes))
        
        for row, proc in enumerate(processes):
            self.process_table.setItem(row, 0, QTableWidgetItem(str(proc['pid'])))
            self.process_table.setItem(row, 1, QTableWidgetItem(proc['name']))
            self.process_table.setItem(row, 2, QTableWidgetItem(f"{proc['cpu']:.1f}"))
            self.process_table.setItem(row, 3, QTableWidgetItem(f"{proc['memory_mb']:.1f}"))
            self.process_table.setItem(row, 4, QTableWidgetItem(proc['status']))
            self.process_table.setItem(row, 5, QTableWidgetItem(proc['user']))
            
            # Color high CPU usage
            if proc['cpu'] > 70:
                for col in range(6):
                    item = self.process_table.item(row, col)
                    if item:
                        item.setBackground(QColor(255, 200, 200))
            elif proc['cpu'] > 30:
                for col in range(6):
                    item = self.process_table.item(row, col)
                    if item:
                        item.setBackground(QColor(255, 230, 200))
        
        self.process_count_label.setText(f"Processes: {len(processes)}")
        
    def show_context_menu(self, position):
        menu = QMenu()
        
        end_task_action = QAction("End Task", self)
        end_task_action.triggered.connect(self.end_selected_task)
        menu.addAction(end_task_action)
        
        end_process_action = QAction("End Process", self)
        end_process_action.triggered.connect(self.end_selected_process)
        menu.addAction(end_process_action)
        
        menu.exec_(self.process_table.viewport().mapToGlobal(position))
        
    def end_selected_task(self):
        selected = self.process_table.currentRow()
        if selected >= 0:
            pid = int(self.process_table.item(selected, 0).text())
            name = self.process_table.item(selected, 1).text()
            
            reply = QMessageBox.question(self, "Confirm End Task", 
                                       f"Are you sure you want to end '{name}' (PID: {pid})?",
                                       QMessageBox.Yes | QMessageBox.No)
            
            if reply == QMessageBox.Yes:
                try:
                    process = psutil.Process(pid)
                    process.terminate()
                    self.statusBar().showMessage(f"Terminated process: {name} (PID: {pid})")
                except psutil.NoSuchProcess:
                    QMessageBox.warning(self, "Error", "Process no longer exists")
                except psutil.AccessDenied:
                    QMessageBox.warning(self, "Error", "Access denied - try running as root")
                
    def end_selected_process(self):
        selected = self.process_table.currentRow()
        if selected >= 0:
            pid = int(self.process_table.item(selected, 0).text())
            name = self.process_table.item(selected, 1).text()
            
            reply = QMessageBox.question(self, "Confirm End Process", 
                                       f"Are you sure you want to forcefully end '{name}' (PID: {pid})?",
                                       QMessageBox.Yes | QMessageBox.No)
            
            if reply == QMessageBox.Yes:
                try:
                    process = psutil.Process(pid)
                    process.kill()
                    self.statusBar().showMessage(f"Killed process: {name} (PID: {pid})")
                except psutil.NoSuchProcess:
                    QMessageBox.warning(self, "Error", "Process no longer exists")
                except psutil.AccessDenied:
                    QMessageBox.warning(self, "Error", "Access denied - try running as root")
                
    def refresh_processes(self):
        self.statusBar().showMessage("Refreshing process list...")
        self.process_updater.terminate()
        self.process_updater.wait()
        self.process_updater.start()
        self.statusBar().showMessage("Process list refreshed")

def main():
    app = QApplication(sys.argv)
    
    # Set application style
    app.setStyle('Fusion')
    
    # Set application font
    font = QFont("DejaVu Sans", 10)
    app.setFont(font)
    
    # Set dark theme
    palette = QPalette()
    palette.setColor(QPalette.Window, QColor(53, 53, 53))
    palette.setColor(QPalette.WindowText, Qt.white)
    palette.setColor(QPalette.Base, QColor(25, 25, 25))
    palette.setColor(QPalette.AlternateBase, QColor(53, 53, 53))
    palette.setColor(QPalette.Text, Qt.white)
    palette.setColor(QPalette.Button, QColor(53, 53, 53))
    palette.setColor(QPalette.ButtonText, Qt.white)
    palette.setColor(QPalette.Highlight, QColor(42, 130, 218))
    palette.setColor(QPalette.HighlightedText, Qt.black)
    app.setPalette(palette)
    
    manager = SystemTaskManager()
    manager.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
EOF

    chmod +x "$APP_DIR/system_task_manager.py"
    print_success "Application created"
}

# Function to create desktop entry
create_desktop_entry() {
    print_status "Creating .desktop file..."

    cat > "$DESKTOP_DIR/system-task-manager.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=System Task Manager
GenericName=Process Manager
Comment=Windows-like Task Manager for Arch Linux
Exec=python3 $APP_DIR/system_task_manager.py
Icon=system-task-manager
Categories=System;Utility;
Terminal=false
StartupWMClass=SystemTaskManager
Keywords=task;manager;process;system;monitor
EOF

    print_success ".desktop file created"
}

# Function to create launcher script
create_launcher() {
    print_status "Creating launcher script..."

    cat > "$BIN_DIR/system-task-manager" << EOF
#!/bin/bash
cd "$APP_DIR"
python3 system_task_manager.py "\$@"
EOF

    chmod +x "$BIN_DIR/system-task-manager"
    print_success "Launcher script created"
}

# Function to create icon
create_icon() {
    print_status "Creating application icon..."
    
    # Use existing system monitor icon as fallback
    if [ -f "/usr/share/icons/Adwaita/256x256/apps/utilities-system-monitor.png" ]; then
        cp "/usr/share/icons/Adwaita/256x256/apps/utilities-system-monitor.png" "$ICON_DIR/system-task-manager.png"
        cp "/usr/share/icons/Adwaita/48x48/apps/utilities-system-monitor.png" "/usr/share/icons/hicolor/48x48/apps/system-task-manager.png"
        cp "/usr/share/icons/Adwaita/32x32/apps/utilities-system-monitor.png" "/usr/share/icons/hicolor/32x32/apps/system-task-manager.png"
        print_success "Icons created using system monitor icon"
    else
        # Create simple text icon as fallback
        cat > "$APP_DIR/icon.svg" << 'EOF'
<svg width="256" height="256" xmlns="http://www.w3.org/2000/svg">
  <rect width="256" height="256" rx="40" fill="#2a82da"/>
  <text x="128" y="140" font-family="Arial" font-size="80" font-weight="bold" fill="white" text-anchor="middle">TM</text>
</svg>
EOF
        print_success "Simple icon created"
    fi
}

# Function to update icon cache
update_icon_cache() {
    print_status "Updating icon cache..."
    if command_exists gtk-update-icon-cache; then
        gtk-update-icon-cache -f -t /usr/share/icons/hicolor
    fi
    print_success "Icon cache updated"
}

# Function to show usage
show_usage() {
    echo "System Task Manager Installer for Arch Linux"
    echo "Usage: sudo ./install_system_task_manager.sh [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -u, --uninstall Uninstall the task manager"
    echo ""
}

# Function to uninstall
uninstall() {
    print_status "Uninstalling System Task Manager..."
    
    rm -rf "$APP_DIR"
    rm -f "$BIN_DIR/system-task-manager"
    rm -f "$DESKTOP_DIR/system-task-manager.desktop"
    rm -f "/usr/share/icons/hicolor/256x256/apps/system-task-manager.png" 2>/dev/null
    rm -f "/usr/share/icons/hicolor/48x48/apps/system-task-manager.png" 2>/dev/null
    rm -f "/usr/share/icons/hicolor/32x32/apps/system-task-manager.png" 2>/dev/null
    
    update_icon_cache
    
    print_success "System Task Manager uninstalled"
}

# Main installation function
main_installation() {
    check_root
    
    print_status "Starting installation of System Task Manager..."
    
    install_dependencies
    create_directories
    create_application
    create_desktop_entry
    create_launcher
    create_icon
    update_icon_cache
    
    print_success "=========================================="
    print_success "INSTALLATION COMPLETED SUCCESSFULLY!"
    print_success "=========================================="
    echo ""
    print_success "Application installed to: $APP_DIR"
    print_success "Launcher script: $BIN_DIR/system-task-manager"
    print_success "Desktop file: $DESKTOP_DIR/system-task-manager.desktop"
    echo ""
    print_success "You can now find 'System Task Manager' in your application menu!"
    print_success "Or run it from terminal with: system-task-manager"
    echo ""
    print_warning "Note: To end system processes, you may need to run as root:"
    print_warning "  sudo system-task-manager"
}

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    main_installation
else
    case $1 in
        -h|--help)
            show_usage
            ;;
        -u|--uninstall)
            uninstall
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
fi
