using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.IO;
using System.Media;
using System.IO.Compression;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace AemisTokenPet;
public partial class MainWindow : Window
{
    private readonly List<DateTime> taps = []; private readonly DispatcherTimer speedTimer = new() { Interval = TimeSpan.FromSeconds(5) };
    private string patMessage = "不要再拍我了"; private bool soundEnabled = true; private string selectedSound = "basso"; private string? mascotPath;
    public MainWindow() { InitializeComponent(); speedTimer.Tick += (_, _) => { speedTimer.Stop(); Detail.Text = "点击人物互动"; }; }
    private void WindowDrag(object sender, MouseButtonEventArgs e) { if (e.OriginalSource == Root || e.OriginalSource == Bubble) DragMove(); }
    private void MascotClicked(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true; PlaySound(); Animate(); taps.Add(DateTime.Now); taps.RemoveAll(t => (DateTime.Now - t).TotalSeconds > 3);
        if (taps.Count >= 2) { var seconds = Math.Max(.25, (taps[^1] - taps[0]).TotalSeconds); Detail.Text = $"连点速度 {taps.Count / seconds:F1} 次/秒"; speedTimer.Stop(); speedTimer.Start(); }
        if (taps.Count >= 15) { MainText.Text = patMessage; Caption.Text = "爱弥斯的请求"; Detail.Text = "连点速度 " + Detail.Text.Replace("连点速度 ", ""); var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) }; timer.Tick += (_, _) => { timer.Stop(); Caption.Text = "Windows Token Pet"; MainText.Text = "爱弥斯"; Detail.Text = "点击人物互动"; }; timer.Start(); taps.Clear(); }
    }
    private void Animate() { var scale = new ScaleTransform(1, 1); Mascot.RenderTransform = scale; var a = new DoubleAnimation(1, 1.12, TimeSpan.FromMilliseconds(110)) { AutoReverse = true }; scale.BeginAnimation(ScaleTransform.ScaleXProperty, a); scale.BeginAnimation(ScaleTransform.ScaleYProperty, a); }
    private void PlaySound() { if (!soundEnabled) return; SystemSounds.Asterisk.Play(); }
    private void ToggleSound(object sender, RoutedEventArgs e) => soundEnabled = ((MenuItem)sender).IsChecked;
    private void SetSound(object sender, RoutedEventArgs e) { selectedSound = (string)((MenuItem)sender).Tag; SystemSounds.Beep.Play(); }
    private void MascotSizeChanged(object sender, RoutedPropertyChangedEventArgs<double> e) { if (Mascot is null) return; MascotSizeMenu.Header = $"人物大小 {e.NewValue * 100:F0}%"; Mascot.LayoutTransform = new ScaleTransform(e.NewValue, e.NewValue); Height = 120 + 154 * e.NewValue; }
    private void BubbleSizeChanged(object sender, RoutedPropertyChangedEventArgs<double> e) { if (Bubble is null) return; BubbleSizeMenu.Header = $"聊天框大小 {e.NewValue * 100:F0}%"; Bubble.LayoutTransform = new ScaleTransform(e.NewValue, e.NewValue); }
    private void OpacityChanged(object sender, RoutedPropertyChangedEventArgs<double> e) { if (Bubble is not null) { OpacityMenu.Header = $"气泡透明度 {e.NewValue * 100:F0}%"; Bubble.Opacity = e.NewValue; } }
    private void ChooseMascot(object sender, RoutedEventArgs e) { var d = new OpenFileDialog { Filter = "透明 PNG|*.png" }; if (d.ShowDialog() == true) { mascotPath = d.FileName; Mascot.Source = new BitmapImage(new Uri(d.FileName)); } }
    private void ChooseColor(object sender, RoutedEventArgs e) { var d = new System.Windows.Forms.ColorDialog(); if (d.ShowDialog() == System.Windows.Forms.DialogResult.OK) Bubble.Background = new SolidColorBrush(Color.FromRgb(d.Color.R, d.Color.G, d.Color.B)); }
    private void ChoosePatMessage(object sender, RoutedEventArgs e) { var d = new TextPrompt("爱弥斯的连点台词", patMessage); if (d.ShowDialog() == true) patMessage = d.Value; }
    private void ChooseSound(object sender, RoutedEventArgs e) { var d = new OpenFileDialog { Filter = "音频（最多 15 秒）|*.wav;*.mp3;*.wma" }; if (d.ShowDialog() == true) { selectedSound = d.FileName; SystemSounds.Exclamation.Play(); } }
    private void SavePreset(object sender, RoutedEventArgs e) => MessageBox.Show("Windows 版预设将在下一版写入本地 JSON；当前角色修改已即时生效。", "爱弥斯");
    private void ExportPresetPack(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { Filter = "爱弥斯人物预设|*.aemispreset", FileName = "爱弥斯人物预设.aemispreset" }; if (dialog.ShowDialog() != true) return;
        var temp = Path.Combine(Path.GetTempPath(), "aemis-pack-" + Guid.NewGuid()); Directory.CreateDirectory(temp);
        try {
            var imageTarget = Path.Combine(temp, "mascot.png");
            if (!string.IsNullOrEmpty(mascotPath)) File.Copy(mascotPath, imageTarget, true);
            else using (var input = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/Aemis.png")).Stream) using (var output = File.Create(imageTarget)) input.CopyTo(output);
            var color = (Bubble.Background as SolidColorBrush)?.Color ?? Colors.Pink;
            var preset = new PackPreset { Id = Guid.NewGuid().ToString(), Name = "爱弥斯人物预设", MascotPath = "mascot.png", Color = new PackColor { Red = color.R / 255.0, Green = color.G / 255.0, Blue = color.B / 255.0, Alpha = Bubble.Opacity }, MascotSize = Mascot.LayoutTransform is ScaleTransform m ? m.ScaleX : 1, BubbleSize = Bubble.LayoutTransform is ScaleTransform b ? b.ScaleX : 1, PatMessage = patMessage, TapSound = selectedSound, SoundVolume = 1 };
            File.WriteAllText(Path.Combine(temp, "preset.json"), JsonSerializer.Serialize(new PackEnvelope { FormatVersion = 1, Preset = preset }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }));
            if (File.Exists(dialog.FileName)) File.Delete(dialog.FileName); ZipFile.CreateFromDirectory(temp, dialog.FileName);
        } finally { if (Directory.Exists(temp)) Directory.Delete(temp, true); }
    }
    private void ImportPresetPack(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "爱弥斯人物预设|*.aemispreset" }; if (dialog.ShowDialog() != true) return;
        var temp = Path.Combine(Path.GetTempPath(), "aemis-unpack-" + Guid.NewGuid()); Directory.CreateDirectory(temp);
        try {
            ZipFile.ExtractToDirectory(dialog.FileName, temp); var json = Directory.GetFiles(temp, "preset.json", SearchOption.AllDirectories).FirstOrDefault(); if (json is null) throw new InvalidDataException("这不是有效的爱弥斯预设包。");
            var pack = JsonSerializer.Deserialize<PackEnvelope>(File.ReadAllText(json), new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? throw new InvalidDataException("预设包内容无效。"); if (pack.FormatVersion != 1) throw new InvalidDataException("预设包版本暂不支持。");
            var folder = Path.GetDirectoryName(json)!; var image = Path.Combine(folder, pack.Preset.MascotPath); if (File.Exists(image)) { mascotPath = image; Mascot.Source = new BitmapImage(new Uri(image)); }
            patMessage = pack.Preset.PatMessage; selectedSound = pack.Preset.TapSound; Bubble.Background = new SolidColorBrush(Color.FromArgb((byte)(pack.Preset.Color.Alpha * 255), (byte)(pack.Preset.Color.Red * 255), (byte)(pack.Preset.Color.Green * 255), (byte)(pack.Preset.Color.Blue * 255))); MessageBox.Show("已导入：" + pack.Preset.Name, "爱弥斯");
        } catch (Exception ex) { MessageBox.Show(ex.Message, "无法导入预设包"); }
    }
    private void UseDefaultPreset(object sender, RoutedEventArgs e) { MainText.Text = "爱弥斯"; Caption.Text = "Windows Token Pet"; }
    private void RememberPosition(object sender, RoutedEventArgs e) => MessageBox.Show("当前位置将在正式打包版中自动保存。", "爱弥斯");
    private void Quit(object sender, RoutedEventArgs e) => Close();
}

public sealed class PackColor { public double Red { get; set; } public double Green { get; set; } public double Blue { get; set; } public double Alpha { get; set; } }
public sealed class PackPreset { public string Id { get; set; } = ""; public string Name { get; set; } = ""; public string MascotPath { get; set; } = "mascot.png"; public PackColor Color { get; set; } = new(); public double MascotSize { get; set; } = 1; public double BubbleSize { get; set; } = 1; public string PatMessage { get; set; } = "不要再拍我了"; public string TapSound { get; set; } = "basso"; public string? CustomSoundPath { get; set; } public double SoundVolume { get; set; } = 1; }
public sealed class PackEnvelope { public int FormatVersion { get; set; } public PackPreset Preset { get; set; } = new(); }

public sealed class TextPrompt : Window
{
    private readonly TextBox box = new(); public string Value => box.Text;
    public TextPrompt(string title, string value) { Title = title; Width = 330; Height = 145; WindowStartupLocation = WindowStartupLocation.CenterScreen; var panel = new StackPanel { Margin = new Thickness(14) }; box.Text = value; panel.Children.Add(box); var ok = new Button { Content = "确定", Margin = new Thickness(0, 12, 0, 0) }; ok.Click += (_, _) => DialogResult = true; panel.Children.Add(ok); Content = panel; }
}
