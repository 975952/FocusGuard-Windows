using System;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

// 专注守卫启动画面：轻量 WPF 程序，仅依赖 CLR，冷启动约 0.3~0.5 秒。
// 主程序（PowerShell）启动它后完成重初始化，主窗口渲染完成时置位
// Local\FocusGuardCN_SplashClose 事件，本程序收到后关闭；30 秒看门狗兜底自闭。
public static class FocusGuardSplash
{
    private const string CloseEventName = @"Local\FocusGuardCN_SplashClose";

    [STAThread]
    public static void Main()
    {
        // 主程序已在运行时（再次点击 exe / 启动器）不显示加载画面：
        // 主程序会自己唤起已有窗口，这里直接退出。
        bool alreadyRunning = false;
        try
        {
            using (Mutex.OpenExisting(@"Local\FocusGuardCN_SingleInstance")) { }
            alreadyRunning = true;
        }
        catch { }
        if (alreadyRunning) return;

        // 启动器与主程序都可能拉起启动画面，同名互斥体保证只显示一个
        bool createdNew;
        using (var instanceMutex = new Mutex(true, @"Local\FocusGuardCN_SplashMutex", out createdNew))
        {
            if (!createdNew) return;
            RunWindow();
        }
    }

    private static void RunWindow()
    {
        EventWaitHandle closeEvent;
        try
        {
            closeEvent = new EventWaitHandle(false, EventResetMode.ManualReset, CloseEventName);
        }
        catch
        {
            closeEvent = null;
        }

        var window = new Window
        {
            Width = 380,
            Height = 210,
            Title = "专注守卫",
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false,
            Topmost = true,
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
            Background = new SolidColorBrush(Color.FromRgb(0xF3, 0xF6, 0xF2)),
            FontFamily = new FontFamily("Microsoft YaHei UI")
        };

        var frame = new Border
        {
            BorderBrush = new SolidColorBrush(Color.FromRgb(0xDD, 0xE5, 0xDF)),
            BorderThickness = new Thickness(1),
            Child = BuildContent()
        };
        window.Content = frame;

        if (closeEvent != null)
        {
            var waiter = new Thread(() =>
            {
                closeEvent.WaitOne(TimeSpan.FromSeconds(30));
                try
                {
                    window.Dispatcher.BeginInvoke(new Action(() => window.Close()));
                }
                catch { }
            });
            waiter.IsBackground = true;
            waiter.Start();
        }
        else
        {
            // 事件不可用时退化为一闪而过，绝不长期停留
            var fallback = new Thread(() =>
            {
                Thread.Sleep(TimeSpan.FromSeconds(8));
                try
                {
                    window.Dispatcher.BeginInvoke(new Action(() => window.Close()));
                }
                catch { }
            });
            fallback.IsBackground = true;
            fallback.Start();
        }

        var app = new Application();
        app.Run(window);
    }

    private static UIElement BuildContent()
    {
        var root = new Grid();

        var column = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center
        };

        // 与应用图标同款的圆环标记
        var icon = new Grid { Width = 46, Height = 46, Margin = new Thickness(0, 0, 0, 14) };
        var disc = new Ellipse { Fill = new SolidColorBrush(Color.FromRgb(0x12, 0x5C, 0x43)) };
        var ring = new Ellipse
        {
            Width = 24,
            Height = 24,
            Stroke = new SolidColorBrush(Color.FromRgb(0x73, 0xDE, 0xAC)),
            StrokeThickness = 3
        };
        var dot = new Ellipse { Width = 7, Height = 7, Fill = new SolidColorBrush(Color.FromRgb(0xF7, 0xFF, 0xFA)) };
        icon.Children.Add(disc);
        icon.Children.Add(ring);
        icon.Children.Add(dot);
        column.Children.Add(icon);

        column.Children.Add(new TextBlock
        {
            Text = "专注守卫",
            FontSize = 20,
            FontWeight = FontWeights.Bold,
            Foreground = new SolidColorBrush(Color.FromRgb(0x17, 0x21, 0x1D)),
            HorizontalAlignment = HorizontalAlignment.Center
        });

        column.Children.Add(new TextBlock
        {
            Text = "正在启动…",
            FontSize = 11,
            Foreground = new SolidColorBrush(Color.FromRgb(0x68, 0x73, 0x6E)),
            Margin = new Thickness(0, 6, 0, 16),
            HorizontalAlignment = HorizontalAlignment.Center
        });

        column.Children.Add(new ProgressBar
        {
            Width = 200,
            Height = 4,
            IsIndeterminate = true,
            Foreground = new SolidColorBrush(Color.FromRgb(0x16, 0x7A, 0x57)),
            Background = new SolidColorBrush(Color.FromRgb(0xDD, 0xE5, 0xDF)),
            BorderThickness = new Thickness(0)
        });

        root.Children.Add(column);
        return root;
    }
}
