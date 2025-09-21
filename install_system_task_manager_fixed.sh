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
#!/usr/bin/env python3
import sys
import psutil
import time
import os
import subprocess
import signal
from datetime import datetime
from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                              QHBoxLayout, QTableWidget, QTableWidgetItem, 
                              QPushButton, QLabel, QHeaderView, QTabWidget,
                              QSplitter, QProgressBar, QTreeWidget, QTreeWidgetItem,
                              QMenu, QMessageBox, QLineEdit, QToolBar, QStatusBar,
                              QComboBox, QGroupBox, QGridLayout, QTextEdit,
                              QFileDialog, QSystemTrayIcon, QCheckBox)
from PySide6.QtCore import Qt, QTimer, QThread, Signal, QSize
from PySide6.QtGui import QIcon, QAction, QPalette, QColor, QFont, QFontDatabase

class ProcessUpdaterThread(QThread):
    update_signal = Signal(list)
    system_stats_signal = Signal(dict)
    
    def run(self):
        while True:
            try:
                # Get system statistics
                cpu_percent = psutil.cpu_percent(interval=0.1)
                memory = psutil.virtual_memory()
                swap = psutil.swap_memory()
                disk = psutil.disk_usage('/')
                net_io = psutil.net_io_counters()
                
                system_stats = {
                    'cpu_percent': cpu_percent,
                    'memory_total': memory.total,
                    'memory_used': memory.used,
                    'memory_percent': memory.percent,
                    'swap_total': swap.total,
                    'swap_used': swap.used,
                    'swap_percent': swap.percent,
                    'disk_total': disk.total,
                    'disk_used': disk.used,
                    'disk_percent': disk.percent,
                    'net_sent': net_io.bytes_sent,
                    'net_recv': net_io.bytes_recv
                }
                self.system_stats_signal.emit(system_stats)
                
                # Get process list
                processes = []
                for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info', 
                                               'status', 'username', 'create_time', 'memory_percent',
                                               'num_threads', 'exe', 'cmdline']):
                    try:
                        mem_info = proc.info['memory_info']
                        memory_mb = mem_info.rss / 1024 / 1024 if mem_info else 0
                        
                        processes.append({
                            'pid': proc.info['pid'],
                            'name': proc.info['name'],
                            'cpu': proc.info['cpu_percent'],
                            'memory_mb': memory_mb,
                            'memory_percent': proc.info['memory_percent'],
                            'status': proc.info['status'],
                            'user': proc.info['username'],
                            'threads': proc.info['num_threads'],
                            'executable': proc.info['exe'] or 'N/A',
                            'cmdline': ' '.join(proc.info['cmdline']) if proc.info['cmdline'] else proc.info['name'],
                            'create_time': datetime.fromtimestamp(proc.info['create_time']).strftime('%Y-%m-%d %H:%M:%S') if proc.info['create_time'] else 'N/A'
                        })
                    except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                        continue
                
                # Sort by CPU usage (descending)
                processes.sort(key=lambda x: x['cpu'], reverse=True)
                self.update_signal.emit(processes)
                time.sleep(2)
                
            except Exception as e:
                print(f"Error in process updater: {e}")
                time.sleep(5)
    
class SystemMonitorThread(QThread):
    monitor_signal = Signal(dict)
    
    def run(self):
        prev_net_sent = psutil.net_io_counters().bytes_sent
        prev_net_recv = psutil.net_io_counters().bytes_recv
        
        while True:
            try:
                # CPU usage per core
                cpu_percent_per_core = psutil.cpu_percent(interval=1, percpu=True)
                
                # Network speed calculation
                net_io = psutil.net_io_counters()
                current_sent = net_io.bytes_sent
                current_recv = net_io.bytes_recv
                
                net_sent_speed = (current_sent - prev_net_sent) / 1024  # KB/s
                net_recv_speed = (current_recv - prev_net_recv) / 1024  # KB/s
                
                prev_net_sent = current_sent
                prev_net_recv = current_recv
                
                # Disk I/O
                disk_io = psutil.disk_io_counters()
                
                monitor_data = {
                    'cpu_per_core': cpu_percent_per_core,
                    'net_sent_speed': net_sent_speed,
                    'net_recv_speed': net_recv_speed,
                    'disk_read_bytes': disk_io.read_bytes if disk_io else 0,
                    'disk_write_bytes': disk_io.write_bytes if disk_io else 0,
                    'timestamp': datetime.now().strftime('%H:%M:%S')
                }
                
                self.monitor_signal.emit(monitor_data)
                
            except Exception as e:
                print(f"Error in system monitor: {e}")
                time.sleep(5)

class SystemTaskManager(QMainWindow):
    def __init__(self):
        super().__init__()
        self.process_data = []
        self.sort_column = 2  # Default sort by CPU
        self.sort_order = Qt.DescendingOrder
        self.init_ui()
        self.start_threads()
        
    def init_ui(self):
        self.setWindowTitle("Advanced System Task Manager - Arch Linux")
        self.setGeometry(100, 100, 1400, 900)
        
        # Load custom font if available
        self.load_fonts()
        
        # Set application style and theme
        self.setup_theme()
        
        # Create central widget and main layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        
        # Create tabs
        self.tabs = QTabWidget()
        main_layout.addWidget(self.tabs)
        
        # Processes tab
        self.create_processes_tab()
        
        # Performance tab
        self.create_performance_tab()
        
        # Startup tab
        self.create_startup_tab()
        
        # Services tab
        self.create_services_tab()
        
        # Create toolbar
        self.create_toolbar()
        
        # Create status bar
        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)
        self.process_count_label = QLabel("Processes: 0")
        self.status_bar.addPermanentWidget(self.process_count_label)
        
        # System tray
        self.setup_system_tray()
        
    def load_fonts(self):
        # Try to load some nice fonts
        font_families = ["Noto Sans", "DejaVu Sans", "Liberation Sans", "Arial"]
        for font in font_families:
            if font in QFontDatabase().families():
                app_font = QFont(font, 10)
                QApplication.setFont(app_font)
                break
    
    def setup_theme(self):
        # Dark theme palette
        dark_palette = QPalette()
        dark_palette.setColor(QPalette.Window, QColor(45, 45, 45))
        dark_palette.setColor(QPalette.WindowText, Qt.white)
        dark_palette.setColor(QPalette.Base, QColor(25, 25, 25))
        dark_palette.setColor(QPalette.AlternateBase, QColor(45, 45, 45))
        dark_palette.setColor(QPalette.ToolTipBase, Qt.white)
        dark_palette.setColor(QPalette.ToolTipText, Qt.white)
        dark_palette.setColor(QPalette.Text, Qt.white)
        dark_palette.setColor(QPalette.Button, QColor(45, 45, 45))
        dark_palette.setColor(QPalette.ButtonText, Qt.white)
        dark_palette.setColor(QPalette.BrightText, Qt.red)
        dark_palette.setColor(QPalette.Link, QColor(42, 130, 218))
        dark_palette.setColor(QPalette.Highlight, QColor(42, 130, 218))
        dark_palette.setColor(QPalette.HighlightedText, Qt.black)
        
        QApplication.setPalette(dark_palette)
        QApplication.setStyle("Fusion")
    
    def create_toolbar(self):
        toolbar = QToolBar("Main Toolbar")
        toolbar.setIconSize(QSize(16, 16))
        self.addToolBar(toolbar)
        
        # Refresh action
        refresh_action = QAction("Refresh", self)
        refresh_action.triggered.connect(self.refresh_processes)
        toolbar.addAction(refresh_action)
        
        toolbar.addSeparator()
        
        # End process actions
        end_task_action = QAction("End Task", self)
        end_task_action.triggered.connect(self.end_selected_task)
        toolbar.addAction(end_task_action)
        
        end_process_action = QAction("End Process", self)
        end_process_action.triggered.connect(self.end_selected_process)
        toolbar.addAction(end_process_action)
        
        toolbar.addSeparator()
        
        # New task action
        new_task_action = QAction("Run New Task", self)
        new_task_action.triggered.connect(self.run_new_task)
        toolbar.addAction(new_task_action)
        
    def setup_system_tray(self):
        if QSystemTrayIcon.isSystemTrayAvailable():
            self.tray_icon = QSystemTrayIcon(self)
            self.tray_icon.setToolTip("System Task Manager")
            
            # Create tray menu
            tray_menu = QMenu()
            
            show_action = QAction("Show", self)
            show_action.triggered.connect(self.show)
            tray_menu.addAction(show_action)
            
            hide_action = QAction("Hide", self)
            hide_action.triggered.connect(self.hide)
            tray_menu.addAction(hide_action)
            
            tray_menu.addSeparator()
            
            quit_action = QAction("Quit", self)
            quit_action.triggered.connect(QApplication.quit)
            tray_menu.addAction(quit_action)
            
            self.tray_icon.setContextMenu(tray_menu)
            self.tray_icon.activated.connect(self.tray_icon_activated)
    
    def tray_icon_activated(self, reason):
        if reason == QSystemTrayIcon.DoubleClick:
            self.show()
            self.activateWindow()
    
    def create_processes_tab(self):
        processes_tab = QWidget()
        layout = QVBoxLayout(processes_tab)
        
        # Search box
        search_layout = QHBoxLayout()
        search_layout.addWidget(QLabel("Search:"))
        self.search_box = QLineEdit()
        self.search_box.setPlaceholderText("Search processes...")
        self.search_box.textChanged.connect(self.filter_processes)
        search_layout.addWidget(self.search_box)
        
        # Filter by user
        search_layout.addWidget(QLabel("User:"))
        self.user_filter = QComboBox()
        self.user_filter.addItem("All Users")
        self.user_filter.currentTextChanged.connect(self.filter_processes)
        search_layout.addWidget(self.user_filter)
        
        layout.addLayout(search_layout)
        
        # Process table
        self.process_table = QTableWidget()
        self.process_table.setColumnCount(10)
        self.process_table.setHorizontalHeaderLabels(["PID", "Name", "CPU %", "Memory (MB)", "Memory %", "Status", "User", "Threads", "Command Line", "Start Time"])
        
        header = self.process_table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeToContents)  # PID
        header.setSectionResizeMode(1, QHeaderView.ResizeToContents)  # Name
        header.setSectionResizeMode(2, QHeaderView.ResizeToContents)  # CPU %
        header.setSectionResizeMode(3, QHeaderView.ResizeToContents)  # Memory (MB)
        header.setSectionResizeMode(4, QHeaderView.ResizeToContents)  # Memory %
        header.setSectionResizeMode(5, QHeaderView.ResizeToContents)  # Status
        header.setSectionResizeMode(6, QHeaderView.ResizeToContents)  # User
        header.setSectionResizeMode(7, QHeaderView.ResizeToContents)  # Threads
        header.setSectionResizeMode(8, QHeaderView.Stretch)          # Command Line
        header.setSectionResizeMode(9, QHeaderView.ResizeToContents) # Start Time
        
        self.process_table.setSortingEnabled(True)
        self.process_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.process_table.setContextMenuPolicy(Qt.CustomContextMenu)
        self.process_table.customContextMenuRequested.connect(self.show_context_menu)
        self.process_table.itemDoubleClicked.connect(self.show_process_details)
        self.process_table.horizontalHeader().sectionClicked.connect(self.sort_table)
        
        layout.addWidget(self.process_table)
        
        self.tabs.addTab(processes_tab, "Processes")
    
    def create_performance_tab(self):
        performance_tab = QWidget()
        layout = QVBoxLayout(performance_tab)
        
        # CPU section
        cpu_group = QGroupBox("CPU Performance")
        cpu_layout = QGridLayout(cpu_group)
        
        self.cpu_bars = []
        cpu_count = psutil.cpu_count()
        for i in range(cpu_count):
            label = QLabel(f"Core {i+1}:")
            progress = QProgressBar()
            progress.setMaximum(100)
            progress.setTextVisible(True)
            self.cpu_bars.append(progress)
            
            cpu_layout.addWidget(label, i, 0)
            cpu_layout.addWidget(progress, i, 1)
        
        layout.addWidget(cpu_group)
        
        # Memory section
        mem_group = QGroupBox("Memory")
        mem_layout = QGridLayout(mem_group)
        
        mem_layout.addWidget(QLabel("Physical Memory:"), 0, 0)
        self.mem_bar = QProgressBar()
        self.mem_bar.setMaximum(100)
        self.mem_bar.setTextVisible(True)
        mem_layout.addWidget(self.mem_bar, 0, 1)
        
        mem_layout.addWidget(QLabel("Swap Memory:"), 1, 0)
        self.swap_bar = QProgressBar()
        self.swap_bar.setMaximum(100)
        self.swap_bar.setTextVisible(True)
        mem_layout.addWidget(self.swap_bar, 1, 1)
        
        self.mem_info_label = QLabel()
        self.swap_info_label = QLabel()
        mem_layout.addWidget(self.mem_info_label, 0, 2)
        mem_layout.addWidget(self.swap_info_label, 1, 2)
        
        layout.addWidget(mem_group)
        
        # Network section
        net_group = QGroupBox("Network")
        net_layout = QGridLayout(net_group)
        
        net_layout.addWidget(QLabel("Download:"), 0, 0)
        self.download_label = QLabel("0 KB/s")
        net_layout.addWidget(self.download_label, 0, 1)
        
        net_layout.addWidget(QLabel("Upload:"), 1, 0)
        self.upload_label = QLabel("0 KB/s")
        net_layout.addWidget(self.upload_label, 1, 1)
        
        layout.addWidget(net_group)
        
        # Disk section
        disk_group = QGroupBox("Disk")
        disk_layout = QGridLayout(disk_group)
        
        disk_layout.addWidget(QLabel("Disk Usage:"), 0, 0)
        self.disk_bar = QProgressBar()
        self.disk_bar.setMaximum(100)
        self.disk_bar.setTextVisible(True)
        disk_layout.addWidget(self.disk_bar, 0, 1)
        
        self.disk_info_label = QLabel()
        disk_layout.addWidget(self.disk_info_label, 0, 2)
        
        layout.addWidget(disk_group)
        
        self.tabs.addTab(performance_tab, "Performance")
    
    def create_startup_tab(self):
        startup_tab = QWidget()
        layout = QVBoxLayout(startup_tab)
        
        info_label = QLabel("Startup applications management (Requires systemd analysis)")
        layout.addWidget(info_label)
        
        # Placeholder for startup applications list
        self.startup_table = QTableWidget()
        self.startup_table.setColumnCount(4)
        self.startup_table.setHorizontalHeaderLabels(["Service", "Status", "Description", "Action"])
        layout.addWidget(self.startup_table)
        
        # Refresh startup apps button
        refresh_btn = QPushButton("Refresh Startup Applications")
        refresh_btn.clicked.connect(self.refresh_startup_apps)
        layout.addWidget(refresh_btn)
        
        self.tabs.addTab(startup_tab, "Startup")
    
    def create_services_tab(self):
        services_tab = QWidget()
        layout = QVBoxLayout(services_tab)
        
        # Service management
        service_group = QGroupBox("System Services")
        service_layout = QVBoxLayout(service_group)
        
        self.services_table = QTableWidget()
        self.services_table.setColumnCount(5)
        self.services_table.setHorizontalHeaderLabels(["Service", "Status", "Description", "Startup", "Actions"])
        service_layout.addWidget(self.services_table)
        
        # Service control buttons
        button_layout = QHBoxLayout()
        start_btn = QPushButton("Start Service")
        stop_btn = QPushButton("Stop Service")
        restart_btn = QPushButton("Restart Service")
        
        start_btn.clicked.connect(self.start_service)
        stop_btn.clicked.connect(self.stop_service)
        restart_btn.clicked.connect(self.restart_service)
        
        button_layout.addWidget(start_btn)
        button_layout.addWidget(stop_btn)
        button_layout.addWidget(restart_btn)
        button_layout.addStretch()
        
        service_layout.addLayout(button_layout)
        layout.addWidget(service_group)
        
        # Refresh services button
        refresh_btn = QPushButton("Refresh Services")
        refresh_btn.clicked.connect(self.refresh_services)
        layout.addWidget(refresh_btn)
        
        self.tabs.addTab(services_tab, "Services")
    
    def start_threads(self):
        # Start process updater thread
        self.process_updater = ProcessUpdaterThread()
        self.process_updater.update_signal.connect(self.update_process_list)
        self.process_updater.system_stats_signal.connect(self.update_system_stats)
        self.process_updater.start()
        
        # Start system monitor thread
        self.system_monitor = SystemMonitorThread()
        self.system_monitor.monitor_signal.connect(self.update_performance_monitor)
        self.system_monitor.start()
    
    def update_process_list(self, processes):
        self.process_data = processes
        self.filter_processes()
        
        # Update user filter
        current_user = self.user_filter.currentText()
        self.user_filter.blockSignals(True)
        self.user_filter.clear()
        self.user_filter.addItem("All Users")
        
        users = set()
        for proc in processes:
            users.add(proc['user'])
        
        for user in sorted(users):
            self.user_filter.addItem(user)
        
        if current_user in [self.user_filter.itemText(i) for i in range(self.user_filter.count())]:
            self.user_filter.setCurrentText(current_user)
        else:
            self.user_filter.setCurrentText("All Users")
        
        self.user_filter.blockSignals(False)
        
        self.process_count_label.setText(f"Processes: {len(processes)}")
    
    def filter_processes(self):
        search_text = self.search_box.text().lower()
        selected_user = self.user_filter.currentText()
        
        filtered_processes = self.process_data
        
        if selected_user != "All Users":
            filtered_processes = [p for p in filtered_processes if p['user'] == selected_user]
        
        if search_text:
            filtered_processes = [p for p in filtered_processes 
                                if search_text in p['name'].lower() 
                                or search_text in p['cmdline'].lower()
                                or search_text in str(p['pid'])]
        
        self.display_processes(filtered_processes)
    
    def display_processes(self, processes):
        self.process_table.setRowCount(len(processes))
        
        for row, proc in enumerate(processes):
            items = [
                QTableWidgetItem(str(proc['pid'])),
                QTableWidgetItem(proc['name']),
                QTableWidgetItem(f"{proc['cpu']:.1f}"),
                QTableWidgetItem(f"{proc['memory_mb']:.1f}"),
                QTableWidgetItem(f"{proc['memory_percent']:.1f}" if proc['memory_percent'] else "N/A"),
                QTableWidgetItem(proc['status']),
                QTableWidgetItem(proc['user']),
                QTableWidgetItem(str(proc['threads'])),
                QTableWidgetItem(proc['cmdline']),
                QTableWidgetItem(proc['create_time'])
            ]
            
            for col, item in enumerate(items):
                item.setFlags(item.flags() & ~Qt.ItemIsEditable)
                self.process_table.setItem(row, col, item)
                
                # Color coding
                if col == 2:  # CPU column
                    if proc['cpu'] > 70:
                        item.setBackground(QColor(255, 100, 100))
                    elif proc['cpu'] > 30:
                        item.setBackground(QColor(255, 200, 100))
                
                elif col == 3:  # Memory column
                    if proc['memory_mb'] > 500:
                        item.setBackground(QColor(100, 100, 255))
    
    def sort_table(self, column):
        self.sort_column = column
        self.filter_processes()
    
    def update_system_stats(self, stats):
        # Update memory info
        mem_used_gb = stats['memory_used'] / 1024 / 1024 / 1024
        mem_total_gb = stats['memory_total'] / 1024 / 1024 / 1024
        self.mem_bar.setValue(int(stats['memory_percent']))
        self.mem_bar.setFormat(f"{stats['memory_percent']:.1f}%")
        self.mem_info_label.setText(f"{mem_used_gb:.1f} GB / {mem_total_gb:.1f} GB")
        
        # Update swap info
        if stats['swap_total'] > 0:
            swap_used_gb = stats['swap_used'] / 1024 / 1024 / 1024
            swap_total_gb = stats['swap_total'] / 1024 / 1024 / 1024
            self.swap_bar.setValue(int(stats['swap_percent']))
            self.swap_bar.setFormat(f"{stats['swap_percent']:.1f}%")
            self.swap_info_label.setText(f"{swap_used_gb:.1f} GB / {swap_total_gb:.1f} GB")
        else:
            self.swap_bar.setValue(0)
            self.swap_bar.setFormat("No swap")
            self.swap_info_label.setText("No swap configured")
        
        # Update disk info
        disk_used_gb = stats['disk_used'] / 1024 / 1024 / 1024
        disk_total_gb = stats['disk_total'] / 1024 / 1024 / 1024
        self.disk_bar.setValue(int(stats['disk_percent']))
        self.disk_bar.setFormat(f"{stats['disk_percent']:.1f}%")
        self.disk_info_label.setText(f"{disk_used_gb:.1f} GB / {disk_total_gb:.1f} GB")
    
    def update_performance_monitor(self, data):
        # Update CPU cores
        for i, cpu_percent in enumerate(data['cpu_per_core']):
            if i < len(self.cpu_bars):
                self.cpu_bars[i].setValue(int(cpu_percent))
                self.cpu_bars[i].setFormat(f"{cpu_percent:.1f}%")
        
        # Update network
        self.download_label.setText(f"{data['net_recv_speed']:.1f} KB/s")
        self.upload_label.setText(f"{data['net_sent_speed']:.1f} KB/s")
    
    def show_context_menu(self, position):
        selected_row = self.process_table.currentRow()
        if selected_row < 0:
            return
        
        menu = QMenu()
        
        end_task_action = QAction("End Task", self)
        end_task_action.triggered.connect(self.end_selected_task)
        menu.addAction(end_task_action)
        
        end_process_action = QAction("End Process", self)
        end_process_action.triggered.connect(self.end_selected_process)
        menu.addAction(end_process_action)
        
        menu.addSeparator()
        
        details_action = QAction("Show Details", self)
        details_action.triggered.connect(self.show_process_details)
        menu.addAction(details_action)
        
        menu.addSeparator()
        
        priority_menu = menu.addMenu("Set Priority")
        
        priorities = [
            ("Realtime", 0),
            ("High", 1),
            ("Above Normal", 2),
            ("Normal", 3),
            ("Below Normal", 4),
            ("Low", 5)
        ]
        
        for name, level in priorities:
            priority_action = QAction(name, self)
            priority_action.triggered.connect(lambda checked, l=level: self.set_process_priority(l))
            priority_menu.addAction(priority_action)
        
        menu.exec_(self.process_table.viewport().mapToGlobal(position))
    
    def show_process_details(self):
        selected_row = self.process_table.currentRow()
        if selected_row < 0:
            return
        
        pid = int(self.process_table.item(selected_row, 0).text())
        
        try:
            process = psutil.Process(pid)
            details = f"""
Process Details:
---------------
PID: {process.pid}
Name: {process.name()}
Status: {process.status()}
CPU: {process.cpu_percent()}%
Memory: {process.memory_info().rss / 1024 / 1024:.1f} MB
Threads: {process.num_threads()}
User: {process.username()}
Create Time: {datetime.fromtimestamp(process.create_time()).strftime('%Y-%m-%d %H:%M:%S')}
Executable: {process.exe() or 'N/A'}
Command Line: {' '.join(process.cmdline()) if process.cmdline() else 'N/A'}
            """
            
            QMessageBox.information(self, "Process Details", details.strip())
            
        except psutil.NoSuchProcess:
            QMessageBox.warning(self, "Error", "Process no longer exists")
        except Exception as e:
            QMessageBox.warning(self, "Error", f"Could not get process details: {e}")
    
    def end_selected_task(self):
        self.terminate_process(signal.SIGTERM)
    
    def end_selected_process(self):
        self.terminate_process(signal.SIGKILL)
    
    def terminate_process(self, sig):
        selected_row = self.process_table.currentRow()
        if selected_row < 0:
            return
        
        pid = int(self.process_table.item(selected_row, 0).text())
        name = self.process_table.item(selected_row, 1).text()
        
        signal_name = "TERM" if sig == signal.SIGTERM else "KILL"
        reply = QMessageBox.question(self, "Confirm", 
                                   f"Are you sure you want to send {signal_name} to '{name}' (PID: {pid})?",
                                   QMessageBox.Yes | QMessageBox.No)
        
        if reply == QMessageBox.Yes:
            try:
                process = psutil.Process(pid)
                if sig == signal.SIGTERM:
                    process.terminate()
                else:
                    process.kill()
                
                self.status_bar.showMessage(f"Sent {signal_name} to process: {name} (PID: {pid})")
                
            except psutil.NoSuchProcess:
                QMessageBox.warning(self, "Error", "Process no longer exists")
            except psutil.AccessDenied:
                QMessageBox.warning(self, "Error", "Access denied - try running as root")
            except Exception as e:
                QMessageBox.warning(self, "Error", f"Could not terminate process: {e}")
    
    def set_process_priority(self, priority_level):
        selected_row = self.process_table.currentRow()
        if selected_row < 0:
            return
        
        pid = int(self.process_table.item(selected_row, 0).text())
        name = self.process_table.item(selected_row, 1).text()
        
        try:
            process = psutil.Process(pid)
            process.nice(priority_level)
            self.status_bar.showMessage(f"Set priority for {name} (PID: {pid})")
            
        except psutil.NoSuchProcess:
            QMessageBox.warning(self, "Error", "Process no longer exists")
        except psutil.AccessDenied:
            QMessageBox.warning(self, "Error", "Access denied - requires root privileges")
        except Exception as e:
            QMessageBox.warning(self, "Error", f"Could not set priority: {e}")
    
    def run_new_task(self):
        command, ok = QLineEdit.getText(self, "Run New Task", "Enter command to run:")
        if ok and command.strip():
            try:
                subprocess.Popen(command.strip(), shell=True)
                self.status_bar.showMessage(f"Started: {command}")
            except Exception as e:
                QMessageBox.warning(self, "Error", f"Could not run command: {e}")
    
    def refresh_processes(self):
        self.status_bar.showMessage("Refreshing process list...")
        self.search_box.clear()
        self.user_filter.setCurrentText("All Users")
        self.status_bar.showMessage("Process list refreshed")
    
    def refresh_startup_apps(self):
        # Placeholder for startup apps refresh
        self.status_bar.showMessage("Startup applications refreshed")
    
    def refresh_services(self):
        # Placeholder for services refresh
        self.status_bar.showMessage("Services list refreshed")
    
    def start_service(self):
        selected_row = self.services_table.currentRow()
        if selected_row >= 0:
            service_name = self.services_table.item(selected_row, 0).text()
            try:
                subprocess.run(["sudo", "systemctl", "start", service_name], check=True)
                self.status_bar.showMessage(f"Started service: {service_name}")
            except subprocess.CalledProcessError:
                QMessageBox.warning(self, "Error", f"Failed to start service: {service_name}")
    
    def stop_service(self):
        selected_row = self.services_table.currentRow()
        if selected_row >= 0:
            service_name = self.services_table.item(selected_row, 0).text()
            try:
                subprocess.run(["sudo", "systemctl", "stop", service_name], check=True)
                self.status_bar.showMessage(f"Stopped service: {service_name}")
            except subprocess.CalledProcessError:
                QMessageBox.warning(self, "Error", f"Failed to stop service: {service_name}")
    
    def restart_service(self):
        selected_row = self.services_table.currentRow()
        if selected_row >= 0:
            service_name = self.services_table.item(selected_row, 0).text()
            try:
                subprocess.run(["sudo", "systemctl", "restart", service_name], check=True)
                self.status_bar.showMessage(f"Restarted service: {service_name}")
            except subprocess.CalledProcessError:
                QMessageBox.warning(self, "Error", f"Failed to restart service: {service_name}")
    
    def closeEvent(self, event):
        # Clean up threads
        if hasattr(self, 'process_updater'):
            self.process_updater.terminate()
            self.process_updater.wait()
        
        if hasattr(self, 'system_monitor'):
            self.system_monitor.terminate()
            self.system_monitor.wait()
        
        event.accept()

def main():
    app = QApplication(sys.argv)
    
    # Set application metadata
    app.setApplicationName("Advanced System Task Manager")
    app.setApplicationVersion("2.0")
    app.setOrganizationName("ArchLinux")
    
    # Check if running as root for full functionality
    if os.geteuid() != 0:
        print("Warning: Not running as root. Some features may be limited.")
    
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
