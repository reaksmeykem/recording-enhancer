# Recording Enhancer - modern UI (dockset.app style, SVG vector icons)
# Lists Motionik recordings, merges microphone.webm into the video, applies:
# declip -> high-pass -> denoise -> compressor -> loudness normalization
# Also enhances any picked video's own audio when no mic track exists.
# Launch: powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File enhance-gui.ps1
param([switch]$SelfTest)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

$root = "C:\Users\User\Motionik-Recordings"

function Get-Tool([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $g = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*" -Recurse -Filter "$name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { return $g.FullName }
    throw "$name.exe not found. Install ffmpeg first."
}
$ffmpeg  = Get-Tool "ffmpeg"
$ffprobe = Get-Tool "ffprobe"
Add-Type -AssemblyName System.Windows.Forms

# videos folder: remembered between launches (videos-folder.txt next to this script)
$defaultRoot  = "C:\Users\User\Motionik-Recordings"
$settingsFile = Join-Path $PSScriptRoot "videos-folder.txt"
$root = $defaultRoot
if (Test-Path $settingsFile) {
    $saved = (Get-Content $settingsFile -Raw -ErrorAction SilentlyContinue)
    if ($saved) { $saved = $saved.Trim() }
    if ($saved -and (Test-Path $saved)) { $root = $saved }
}

function New-Brush([string]$hex) {
    return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Recording Enhancer" Height="560" Width="720"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        WindowStyle="None" Background="#0A0A0C" FontFamily="Segoe UI"
        ToolTipService.InitialShowDelay="250">
  <Window.Resources>
    <LinearGradientBrush x:Key="Accent" StartPoint="0,0" EndPoint="1,0">
      <GradientStop Color="#5E5CE6" Offset="0"/>
      <GradientStop Color="#BF5AF2" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="ProgressFill" StartPoint="0,0" EndPoint="1,0">
      <GradientStop Color="#5E5CE6" Offset="0"/>
      <GradientStop Color="#BF5AF2" Offset="1"/>
    </LinearGradientBrush>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="#26262B"/>
      <Setter Property="Foreground" Value="#EDEDF2"/>
      <Setter Property="BorderBrush" Value="#3A3A40"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Padding" Value="9,5"/>
    </Style>
    <!-- circular SVG icon button, dark -->
    <Style x:Key="IconBtn" TargetType="Button">
      <Setter Property="Background" Value="#141417"/>
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="#2A2A2E" BorderThickness="1" CornerRadius="20">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1F1F24"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#3A3A42"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- circular SVG icon button, white primary -->
    <Style x:Key="IconBtnPrimary" TargetType="Button" BasedOn="{StaticResource IconBtn}">
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="Width" Value="44"/>
      <Setter Property="Height" Value="44"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="22">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#E8E8ED"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="IconTiny" TargetType="Button" BasedOn="{StaticResource IconBtn}">
      <Setter Property="Width" Value="26"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="13">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#232329"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="RecItemStyle" TargetType="ListBoxItem">
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" CornerRadius="12" Padding="10,8" Margin="4,2"
                    Background="Transparent" BorderThickness="1" BorderBrush="Transparent">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#121216"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#18181D"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#2F2F3A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ModernProgress" TargetType="ProgressBar">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid>
              <Border x:Name="PART_Track" Background="#17171B" CornerRadius="3"/>
              <Border x:Name="PART_Indicator" HorizontalAlignment="Left" CornerRadius="3"
                      Background="{StaticResource ProgressFill}"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- dark rounded combo box + items, matches circular icon buttons -->
    <Style x:Key="DarkComboItem" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#EDEDF2"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="8" Padding="10,7" Margin="4,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1F1F24"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#26262B"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DarkCombo" TargetType="ComboBox">
      <Setter Property="Foreground" Value="#F5F5F7"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource DarkComboItem}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Focusable="False" ClickMode="Press"
                             IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Bd" Background="#141417" BorderBrush="#2A2A2E" BorderThickness="1" CornerRadius="20">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="32"/>
                        </Grid.ColumnDefinitions>
                        <Path Grid.Column="1" Data="M0,0 L4,4.2 L8,0" Stroke="#A0A0A8" StrokeThickness="1.8"
                              StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"
                              HorizontalAlignment="Center" VerticalAlignment="Center" Stretch="None"/>
                      </Grid>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Bd" Property="BorderBrush" Value="#3A3A42"/>
                        <Setter TargetName="Bd" Property="Background" Value="#1A1A1F"/>
                      </Trigger>
                      <Trigger Property="IsChecked" Value="True">
                        <Setter TargetName="Bd" Property="BorderBrush" Value="#5E5CE6"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <!-- selected text; SelectedItem is a ComboBoxItem, so show its Content -->
              <TextBlock IsHitTestVisible="False" Margin="15,0,30,0" VerticalAlignment="Center"
                         Text="{Binding SelectedItem.Content, RelativeSource={RelativeSource TemplatedParent}}"/>
              <Popup AllowsTransparency="True" Placement="Bottom" PopupAnimation="Fade" Focusable="False"
                     IsOpen="{TemplateBinding IsDropDownOpen}">
                <Border Background="#1C1C21" BorderBrush="#2F2F36" BorderThickness="1" CornerRadius="12"
                        Margin="0,5,0,0" MinWidth="{TemplateBinding ActualWidth}" Padding="2">
                  <ScrollViewer MaxHeight="170" VerticalScrollBarVisibility="Auto">
                    <ItemsPresenter/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- floating pill navbar -->
    <Border Grid.Row="0" Background="#131316" BorderBrush="#222226" BorderThickness="1"
            CornerRadius="22" Padding="14,8">
      <Grid>
        <StackPanel Orientation="Horizontal">
          <!-- gradient app tile with waveform SVG -->
          <Border Width="24" Height="24" CornerRadius="8" Background="{StaticResource Accent}">
            <Path Data="M5,8.5 L5,15.5 M9.5,5.5 L9.5,18.5 M14,7.5 L14,16.5 M18.5,10 L18.5,14"
                  Stroke="#FFFFFF" StrokeThickness="1.8" StrokeStartLineCap="Round"
                  StrokeEndLineCap="Round" Stretch="None"/>
          </Border>
          <StackPanel VerticalAlignment="Center" Margin="10,0,0,0">
            <TextBlock Text="Recording Enhancer" Foreground="#F5F5F7" FontWeight="Bold" FontSize="13"/>
          </StackPanel>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <TextBlock x:Name="tbCount" Text="" Foreground="#8E8E93" FontSize="11.5"
                     VerticalAlignment="Center" Margin="0,0,6,0"/>
          <Button x:Name="btnChangeFolder" Style="{StaticResource IconTiny}" ToolTip="Change videos folder"
                  Margin="0,0,6,0">
            <Path Data="M3,6.5 C3,5.4 3.9,4.5 5,4.5 L9.5,4.5 L11.5,6.5 L19,6.5 C20.1,6.5 21,7.4 21,8.5 L21,17.5 C21,18.6 20.1,19.5 19,19.5 L5,19.5 C3.9,19.5 3,18.6 3,17.5 Z M12,10.5 L12,16.5 M9,13.5 L15,13.5"
                  Stroke="#A0A0A8" StrokeThickness="1.7" StrokeStartLineCap="Round"
                  StrokeEndLineCap="Round" StrokeLineJoin="Round" Stretch="Uniform" Width="14" Height="14"/>
          </Button>
          <Button x:Name="btnMin" Style="{StaticResource IconTiny}" ToolTip="Minimize">
            <Path Data="M6,12 L18,12" Stroke="#A0A0A8" StrokeThickness="1.8"
                  StrokeStartLineCap="Round" StrokeEndLineCap="Round" Stretch="None"/>
          </Button>
          <Button x:Name="btnClose" Style="{StaticResource IconTiny}" ToolTip="Close">
            <Path Data="M7,7 L17,17 M17,7 L7,17" Stroke="#A0A0A8" StrokeThickness="1.8"
                  StrokeStartLineCap="Round" StrokeEndLineCap="Round" Stretch="None"/>
          </Button>
        </StackPanel>
      </Grid>
    </Border>

    <!-- hero -->
    <StackPanel Grid.Row="1" Margin="6,16,6,12">
      <TextBlock Text="Your recordings." Foreground="#F5F5F7" FontSize="24" FontWeight="Bold"/>
      <TextBlock Text="Pick a clip and enhance it: declip, denoise, even levels."
                 Foreground="#8E8E93" FontSize="12" Margin="0,5,0,0"/>
      <Rectangle Height="2" RadiusX="1" RadiusY="1" Fill="{StaticResource Accent}" Opacity="0.55"
                 HorizontalAlignment="Left" Width="110" Margin="0,10,0,0"/>
      <TextBlock x:Name="tbRoot" Text="" Foreground="#5A5A62" FontSize="10.5" Margin="0,8,0,0"
                 TextTrimming="CharacterEllipsis"/>
      <!-- search recordings by name -->
      <Grid Margin="0,10,0,0">
        <TextBox x:Name="txtSearch" Height="34" VerticalContentAlignment="Center" Padding="10,0,32,0"
                 Background="#131316" BorderBrush="#222226" Foreground="#F2F2F5" CaretBrush="#BF5AF2"
                 FontSize="12" BorderThickness="1" ToolTip="Search recordings by name"/>
        <TextBlock x:Name="tbSearchHint" Text="Search..." Foreground="#6A6A72" FontSize="12"
                   Margin="11,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        <Path Data="M10.5,3 A7.5,7.5 0 1 1 10.49,3 M15.8,15.8 L21,21"
              Stroke="#6A6A72" StrokeThickness="1.6" Stretch="None"
              HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0"/>
      </Grid>
    </StackPanel>

    <!-- recording cards -->
    <Grid Grid.Row="2">
      <ListBox x:Name="lvRecordings" Background="Transparent"
               BorderThickness="0" ItemContainerStyle="{StaticResource RecItemStyle}"
               ScrollViewer.HorizontalScrollBarVisibility="Disabled" Padding="0,0,12,0"
               VirtualizingPanel.ScrollUnit="Pixel">
      <ListBox.ItemTemplate>
        <DataTemplate>
          <DockPanel LastChildFill="True">
            <!-- right status icons -->
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center" Margin="8,0,2,0">
              <TextBlock Text="{Binding Duration}" Foreground="#74747C" FontSize="11"
                         VerticalAlignment="Center" Margin="0,0,10,0"/>
              <Grid ToolTipService.InitialShowDelay="100"
                    ToolTipService.ShowOnDisabled="True">
                <Grid.ToolTip>
                  <ToolTip Content="{Binding MicTip}"/>
                </Grid.ToolTip>
                <Path Data="M12,3.2 A3.1,3.1 0 0 1 15.1,6.3 L15.1,10.7 A3.1,3.1 0 0 1 8.9,10.7 L8.9,6.3 A3.1,3.1 0 0 1 12,3.2 M6.2,10.7 A5.8,5.8 0 0 0 17.8,10.7 M12,16.5 L12,20 M8.8,20 L15.2,20"
                      Stroke="{Binding MicBrush}" StrokeThickness="1.7" StrokeStartLineCap="Round"
                      StrokeEndLineCap="Round" Stretch="Uniform" Width="17" Height="17"/>
              </Grid>
              <Grid Visibility="{Binding EnhancedVis}" Margin="8,0,0,0"
                    ToolTip="Enhanced version is ready - press play to hear it">
                <Path Data="M12,2.5 A9.5,9.5 0 1 1 11.99,2.5 M8,12.2 L11,15.2 L16.4,9.6"
                      Stroke="#4ADE80" StrokeThickness="1.7" StrokeStartLineCap="Round"
                      StrokeEndLineCap="Round" Stretch="Uniform" Width="17" Height="17"/>
              </Grid>
            </StackPanel>
            <!-- icon tile -->
            <Border DockPanel.Dock="Left" Width="30" Height="30" CornerRadius="9"
                    Background="{Binding TileBg}" VerticalAlignment="Center">
              <Path Data="M4,2.2 L11.5,7 L4,11.8 Z" Fill="{Binding GlyphBrush}"
                    Stretch="Uniform" Width="12" Height="12"
                    HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <!-- name + meta -->
            <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
              <TextBlock Text="{Binding Name}" Foreground="#F2F2F5" FontWeight="SemiBold" FontSize="12.5"
                         TextTrimming="CharacterEllipsis"/>
              <TextBlock Text="{Binding Date}" Foreground="#74747C" FontSize="11" Margin="0,2,0,0"/>
            </StackPanel>
          </DockPanel>
        </DataTemplate>
      </ListBox.ItemTemplate>
    </ListBox>
      <!-- empty state -->
      <StackPanel x:Name="emptyState" Visibility="Collapsed" VerticalAlignment="Center" HorizontalAlignment="Center">
        <Path Data="M10,4 L4,4 C2.9,4 2,4.9 2,6 L2,18 C2,19.1 2.9,20 4,20 L20,20 C21.1,20 22,19.1 22,18 L22,8 C22,6.9 21.1,6 20,6 L12,6 Z"
              Stroke="#3A3A42" StrokeThickness="1.5" Stretch="Uniform" Width="46" Height="46" HorizontalAlignment="Center"/>
        <TextBlock Text="No recordings found" Foreground="#8E8E93" FontSize="14" FontWeight="SemiBold"
                   HorizontalAlignment="Center" Margin="0,12,0,0"/>
        <TextBlock Text="Pick your recordings folder (folder icon above) or add a video/audio file (document icon below)."
                   Foreground="#5A5A62" FontSize="11.5" HorizontalAlignment="Center" Margin="0,5,0,0"/>
      </StackPanel>
    </Grid>


    <!-- action bar: SVG icon buttons + status -->
    <Grid Grid.Row="3" Margin="2,12,2,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Orientation="Horizontal">
        <ComboBox x:Name="cbPreset" Style="{StaticResource DarkCombo}" Width="132" Height="40" VerticalAlignment="Center" Margin="0,0,8,0"
                  SelectedIndex="0" ToolTip="Natural = gentle cleanup only. Classic = the original processing chain.">
          <ComboBoxItem Content="Natural"/>
          <ComboBoxItem Content="Classic"/>
        </ComboBox>
        <Button x:Name="btnEnhance" Height="40" Padding="18,0" Margin="0,0,10,0" Cursor="Hand"
                ToolTip="Enhance selected recording">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border x:Name="Bd" Background="{StaticResource Accent}" CornerRadius="20"
                      Padding="{TemplateBinding Padding}">
                <StackPanel Orientation="Horizontal">
                  <Path Data="M7,1.5 L8.7,5.3 L12.5,7 L8.7,8.7 L7,12.5 L5.3,8.7 L1.5,7 L5.3,5.3 Z M16.5,11.5 L17.7,14.3 L20.5,15.5 L17.7,16.7 L16.5,19.5 L15.3,16.7 L12.5,15.5 L15.3,14.3 Z M18.5,3 L19.2,4.8 L21,5.5 L19.2,6.2 L18.5,8 L17.8,6.2 L16,5.5 L17.8,4.8 Z"
                        Fill="#FFFFFF" Stretch="Uniform" Width="14" Height="14"
                        VerticalAlignment="Center"/>
                  <TextBlock Text="Enhance" Foreground="#FFFFFF" FontWeight="Bold" FontSize="13"
                             VerticalAlignment="Center" Margin="8,0,0,0"/>
                </StackPanel>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Bd" Property="Opacity" Value="0.87"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                  <Setter TargetName="Bd" Property="Opacity" Value="0.35"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Button.Template>
        </Button>
        <Button x:Name="btnPlay" Style="{StaticResource IconBtn}" ToolTip="Play result (falls back to original)"
                Margin="0,0,8,0">
          <Path Data="M8,5 L19,12 L8,19 Z" Fill="#C9C9D0" Stretch="Uniform" Width="17" Height="17"/>
        </Button>
        <Button x:Name="btnOpenFolder" Style="{StaticResource IconBtn}" ToolTip="Open recording folder"
                Margin="0,0,8,0">
          <Path Data="M10,4 L4,4 C2.9,4 2,4.9 2,6 L2,18 C2,19.1 2.9,20 4,20 L20,20 C21.1,20 22,19.1 22,18 L22,8 C22,6.9 21.1,6 20,6 L12,6 Z"
                Fill="#C9C9D0" Stretch="Uniform" Width="18" Height="18"/>
        </Button>
        <Button x:Name="btnBrowse" Style="{StaticResource IconBtn}" ToolTip="Pick any video file to enhance"
                Margin="0,0,8,0">
          <Path Data="M14,2 L6,2 C4.9,2 4,2.9 4,4 L4,20 C4,21.1 4.9,22 6,22 L18,22 C19.1,22 20,21.1 20,20 L20,8 Z M16,18 L8,18 L8,16 L16,16 Z M16,14 L8,14 L8,12 L16,12 Z M13,9 L13,3.5 L18.5,9 Z"
                Fill="#C9C9D0" Stretch="Uniform" Width="17" Height="17"/>
        </Button>
        <Button x:Name="btnRefresh" Style="{StaticResource IconBtn}" ToolTip="Refresh list">
          <Path Data="M17.65,6.35 A7.95,7.95 0 0 0 12,4 A8,8 0 1 0 19.73,14 L17.66,14 A6,6 0 1 1 12,6 C13.93,6 15.63,6.82 16.86,8.05 L14,11 L21,11 L21,4 Z"
                Fill="#C9C9D0" Stretch="Uniform" Width="17" Height="17"/>
        </Button>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
        <ProgressBar x:Name="pb" Width="130" Height="6" Minimum="0" Maximum="100"
                     Style="{StaticResource ModernProgress}" Visibility="Collapsed"/>
        <TextBlock x:Name="tbStatus" Text="Select a recording, then enhance."
                   Foreground="#8E8E93" FontSize="11.5" VerticalAlignment="Center" Margin="9,0,0,0"
                   TextTrimming="CharacterEllipsis" MaxWidth="330"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$pb            = $window.FindName("pb")
$lv            = $window.FindName("lvRecordings")
$btnEnhance    = $window.FindName("btnEnhance")
$btnOpenFolder = $window.FindName("btnOpenFolder")
$btnPlay       = $window.FindName("btnPlay")
$btnRefresh    = $window.FindName("btnRefresh")
$btnBrowse     = $window.FindName("btnBrowse")
$btnClose      = $window.FindName("btnClose")
$btnMin        = $window.FindName("btnMin")
$btnChangeFolder = $window.FindName("btnChangeFolder")
$tbRoot        = $window.FindName("tbRoot")
$cbPreset      = $window.FindName("cbPreset")
$tbStatus      = $window.FindName("tbStatus")
$tbCount       = $window.FindName("tbCount")
$txtSearch     = $window.FindName("txtSearch")
$tbSearchHint  = $window.FindName("tbSearchHint")
$emptyState    = $window.FindName("emptyState")

$window.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })
$btnClose.Add_Click({ $window.Close() })
$btnMin.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })

$tbRoot.Text = $root
$btnChangeFolder.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Choose the folder that contains your video recordings"
    $fbd.ShowNewFolderButton = $false
    $fbd.SelectedPath = $root
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $root = $fbd.SelectedPath
        Set-Content -Path $settingsFile -Value $root -Encoding UTF8
        $tbRoot.Text = $root
        $script:lastPath = $null
        Refresh-List
    }
})

$script:proc = $null
$script:progFile = Join-Path $env:TEMP "enhance_progress.txt"
$script:totalDur = 0
$script:outPath = $null
$script:lastPath = $null

function Show-InExplorer([string]$path) {
    # /select with a quoted path is unreliable; pass the path without extra quotes
    Start-Process explorer.exe "/select,$path"
}

# precomputed brushes / item state
$tileBgOn   = New-Brush "#1B3A2A"
$tileBgOff  = New-Brush "#20202E"
$glyphOn    = New-Brush "#5EE89A"
$glyphOff   = New-Brush "#A5A9F5"
$micOn      = New-Brush "#7EB8FF"
$micOff     = New-Brush "#3A3A42"
$enhBg      = New-Brush "#1B2E22"
$visOn      = [System.Windows.Visibility]::Visible
$visOff     = [System.Windows.Visibility]::Collapsed

# Keeps the window painting during synchronous scans (forces pending render to flush).
function Pump-UI {
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

# Visible loading state while the folder is scanned / files are probed.
function Set-Loading([bool]$on) {
    if ($on) {
        $btnEnhance.IsEnabled = $false; $btnRefresh.IsEnabled = $false
        $btnBrowse.IsEnabled = $false; $btnPlay.IsEnabled = $false
        $btnChangeFolder.IsEnabled = $false
        $tbStatus.Text = "Loading recordings..."; $tbStatus.Foreground = New-Brush "#8E8E93"
        $pb.IsIndeterminate = $true; $pb.Visibility = $visOn
        Pump-UI
    } else {
        $pb.IsIndeterminate = $false; $pb.Visibility = $visOff
        Set-Buttons $true; $btnChangeFolder.IsEnabled = $true
        # keep completion messages (e.g. "Done:") but clear the loading text
        if ($tbStatus.Text -like "Loading recordings...*") {
            Set-Status "Select a recording, then enhance." "#8E8E93"
        }
    }
}

function Refresh-List {
    Set-Loading $true
    # remember which recording was selected so a refresh doesn't wipe it
    $selPath = $null
    if ($lv.SelectedItem) { $selPath = $lv.SelectedItem.Path }
    if (-not $selPath -and $script:lastPath) { $selPath = $script:lastPath }

    $items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    # 1) Motionik session folders: <folder>\recording-*.mp4 (+ microphone.webm)
    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | ForEach-Object {
            $mp4 = Get-ChildItem $_.FullName -Filter "recording-*.mp4" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch "ENHANCED|fixed" } |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($mp4) {
                $hasMic = Test-Path (Join-Path $_.FullName "microphone.webm")
                $enh = Get-ChildItem $_.FullName -Filter "*-ENHANCED.mp4" -ErrorAction SilentlyContinue | Select-Object -First 1
                $dur = ""
                try {
                    $d = [double](& $ffprobe -v error -show_entries format=duration -of csv=p=0 $mp4.FullName 2>$null)
                    $dur = "{0:mm\:ss}" -f [TimeSpan]::FromSeconds($d)
                } catch { $dur = "--:--" }
                $items.Add([PSCustomObject]@{
                    Date        = $mp4.LastWriteTime.ToString("MMM d  HH:mm")
                    Duration    = $dur
                    Name        = $_.Name
                    Path        = $mp4.FullName
                    HasMic      = $hasMic
                    TileBg      = if ($enh) { $tileBgOn } else { $tileBgOff }
                    GlyphBrush  = if ($enh) { $glyphOn } else { $glyphOff }
                    MicBrush    = if ($hasMic) { $micOn } else { $micOff }
                    MicTip      = if ($hasMic) { "Microphone track found" } else { "No microphone track (video's own audio will be enhanced)" }
                    EnhancedVis = if ($enh) { $visOn } else { $visOff }
                })
                Set-Status "Loading recordings... $($items.Count) found" "#8E8E93"
                Pump-UI
            }
        }
    # 2) loose video files directly in the chosen folder (e.g. motionik-video-*.mp4 exports)
    #    plus audio-only files (mp3/wav/m4a/...) — the app enhances their voice too.
    Get-ChildItem $root -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -match '^\.(mp4|webm|mkv|mov|mp3|wav|m4a|aac|flac|ogg)$' -and $_.Name -notmatch "ENHANCED"
        } |
        Sort-Object LastWriteTime -Descending | ForEach-Object {
            $dur = ""
            try {
                $d = [double](& $ffprobe -v error -show_entries format=duration -of csv=p=0 $_.FullName 2>$null)
                $dur = "{0:mm\:ss}" -f [TimeSpan]::FromSeconds($d)
            } catch { $dur = "--:--" }
            $hasMic = Test-Path (Join-Path $_.DirectoryName "microphone.webm")
            $enh = (Test-Path (Join-Path $_.DirectoryName ($_.BaseName + "-ENHANCED.mp4"))) -or
                   (Test-Path (Join-Path $_.DirectoryName ($_.BaseName + "-ENHANCED.m4a")))
            $isAudio = $_.Extension -match '^\.(mp3|wav|m4a|aac|flac|ogg)$'
            $items.Add([PSCustomObject]@{
                Date        = $_.LastWriteTime.ToString("MMM d  HH:mm")
                Duration    = $dur
                Name        = $_.Name
                Path        = $_.FullName
                HasMic      = $hasMic
                TileBg      = if ($enh) { $tileBgOn } else { $tileBgOff }
                GlyphBrush  = if ($enh) { $glyphOn } else { $glyphOff }
                MicBrush    = if ($hasMic) { $micOn } else { $micOff }
                MicTip      = if ($isAudio) { "Audio file - voice will be enhanced" } else { if ($hasMic) { "Microphone track found" } else { "No microphone track (video's own audio will be enhanced)" } }
                EnhancedVis = if ($enh) { $visOn } else { $visOff }
            })
            Set-Status "Loading recordings... $($items.Count) found" "#8E8E93"
            Pump-UI
        }
    $lv.ItemsSource = $items
    # restore the selection (by path) after the refresh
    if ($selPath) {
        foreach ($it in $items) {
            if ($it.Path -eq $selPath) { $lv.SelectedItem = $it; break }
        }
    }
    Set-Loading $false
    Apply-Search
}

# Filter the visible recordings by the search box text; drives hint + empty state.
function Apply-Search {
    $items = @($lv.ItemsSource)
    $query = ""
    if ($txtSearch.Text) { $query = $txtSearch.Text.Trim() }
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($lv.ItemsSource)
    if ($view) {
        if ($query) {
            $view.Filter = [Predicate[object]] { param($item) $item.Name -match [regex]::Escape($query) }
        } else {
            $view.Filter = $null
        }
        $visible = @($view | ForEach-Object { $_ }).Count
    } else {
        $visible = $items.Count
    }
    $tbSearchHint.Visibility = if ($query) { $visOff } else { $visOn }
    $emptyState.Visibility = if ($items.Count -eq 0) { $visOn } else { $visOff }
    $tbCount.Text = if ($query -and $items.Count -gt 0 -and $visible -lt $items.Count) { "{0} of {1} recordings" -f $visible, $items.Count }
                    else { "{0} recordings" -f $items.Count }
}
$txtSearch.Add_TextChanged({ Apply-Search })

function Set-Buttons([bool]$enabled) {
    $btnEnhance.IsEnabled = $enabled
    $btnRefresh.IsEnabled = $enabled
    $btnPlay.IsEnabled = $enabled
    $btnBrowse.IsEnabled = $enabled
}

function Test-HasAudio([string]$file) {
    try {
        $s = & $ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 $file 2>$null
        return ($null -ne $s -and "$s".Trim().Length -gt 0)
    } catch { return $false }
}

function Set-Status([string]$text, [string]$color) {
    $tbStatus.Text = $text
    $tbStatus.Foreground = New-Brush $color
}

function Get-LoudGain([string]$audioFile, [string]$preFilter) {
    # Measures the ORIGINAL voice level and the CLEANED voice level,
    # returns the gain (dB) needed so the enhanced voice is exactly as loud as the original.
    function Parse-InputI([string]$ffmpegOutput) {
        $m = [regex]::Match($ffmpegOutput, '\{[^{}]*"input_i"[^{}]*\}')
        if (-not $m.Success) { return $null }
        try {
            $j = $m.Value | ConvertFrom-Json
            return [double]::Parse($j.input_i, [System.Globalization.CultureInfo]::InvariantCulture)
        } catch { return $null }
    }
    try {
        # PowerShell 5.1 turns ffmpeg's stderr banner into a terminating error under
        # $ErrorActionPreference='Stop'; capture must run with 'Continue'.
        $ErrorActionPreference = 'Continue'
        $rawOut   = & $ffmpeg -hide_banner -i $audioFile -af "loudnorm=I=-9:TP=-1.0:LRA=11:print_format=json" -f null - 2>&1 | Out-String
        $srcI     = Parse-InputI $rawOut
        if ($null -eq $srcI) { return $null }
        $cleanOut = & $ffmpeg -hide_banner -i $audioFile -af "$preFilter,loudnorm=I=-9:TP=-1.0:LRA=11:print_format=json" -f null - 2>&1 | Out-String
        $cleanI   = Parse-InputI $cleanOut
        if ($null -eq $cleanI) { return $null }
        $gain = [Math]::Round($srcI - $cleanI, 1)
        if ($gain -lt 0) { $gain = 0 } elseif ($gain -gt 18) { $gain = 18 }
        return $gain
    } catch { return $null }
}

function Start-Enhance($videoPath, $micPath) {
    $dir = Split-Path $videoPath -Parent
    # audio-only input -> audio-only output (.m4a); video input -> .mp4 (video stream-copied)
    $isAudioOnly = $videoPath -match '\.(mp3|wav|m4a|aac|flac|ogg)$'
    $ext = if ($isAudioOnly) { ".m4a" } else { ".mp4" }
    $script:outPath = Join-Path $dir ([IO.Path]::GetFileNameWithoutExtension($videoPath) + "-ENHANCED$ext")
    try { $script:totalDur = [double](& $ffprobe -v error -show_entries format=duration -of csv=p=0 $videoPath 2>$null) } catch { $script:totalDur = 0 }
    Remove-Item $script:progFile -ErrorAction SilentlyContinue

    $useMic = $micPath -and (Test-Path $micPath)
    if (-not $useMic -and -not (Test-HasAudio $videoPath)) {
        $tbStatus.Text = "That file has no audio track (and no microphone.webm) - nothing to enhance."
        return
    }
    $audioFile = if ($useMic) { $micPath } else { $videoPath }

    # denoiser: prefer the local AI model (RNN voice separation), fall back to FFT denoise
    $denoise = "afftdn=nr=12:nf=-30"
    $modelFile = Join-Path $PSScriptRoot "rnnoise-model.rnnn"
    if (Test-Path $modelFile) {
        $modelPath = ($modelFile -replace '\\', '/').Replace(":", "\:")
        $denoise = "arnndn=m='$modelPath'"
    }

    # gentle pro chain (keeps the voice natural): repair -> clean (AI) -> light tone fix ->
    # de-ess -> soft compression. No speechnorm/heavy EQ (those make the voice sound harsh),
    # no dry-blend (that re-imports the original noise).
    $pre = "adeclip,highpass=f=75,$denoise," +
           "equalizer=f=3200:t=q:w=1.4:g=1.5," +
           "equalizer=f=250:t=q:w=1.0:g=-1.5," +
           "deesser=i=0.1:m=0.4:f=0.5," +
           "acompressor=threshold=-24dB:ratio=2.5:attack=15:release=180:makeup=3dB"

    # Natural: minimal processing. Only rumble removal and gentle AI denoise —
    # no declip/EQ/de-ess/compressor, so the voice keeps its own tone and texture.
    if ($cbPreset -and $cbPreset.SelectedItem.Content -eq "Natural") {
        $pre = "highpass=f=60,$denoise"
    }

    # measure original vs cleaned loudness -> restore gain so the voice is NOT quieter after enhancing
    Set-Status "Analyzing voice level..." "#8E8E93"
    $gain = Get-LoudGain $audioFile $pre
    if ($null -eq $gain) { $gain = 0 }
    $filter = "$pre,volume=${gain}dB,alimiter=limit=0.891:level=false"

    if ($isAudioOnly) {
        # audio-only input: no video stream to map
        $argStr = "-y -v error -i `"$videoPath`" " +
                  "-filter_complex `"[0:a]$filter[a]`" -map `"[a]`" " +
                  "-c:a aac -b:a 160k "
    } elseif ($useMic) {
        # separate mic track (Motionik style): enhance the mic audio, keep video as-is
        $argStr = "-y -v error -i `"$videoPath`" -i `"$micPath`" " +
                  "-filter_complex `"[1:a]$filter[a]`" -map 0:v -map `"[a]`" "
    } else {
        # no mic track: enhance the video's own audio
        $argStr = "-y -v error -i `"$videoPath`" " +
                  "-filter_complex `"[0:a]$filter[a]`" -map 0:v -map `"[a]`" "
    }
    if ($isAudioOnly) {
        $argStr += "-progress `"$script:progFile`" `"$script:outPath`""
    } else {
        $argStr += "-c:v copy -c:a aac -b:a 160k -shortest " +
                   "-progress `"$script:progFile`" `"$script:outPath`""
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffmpeg
    $psi.Arguments = $argStr
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $script:proc = [System.Diagnostics.Process]::Start($psi)
    Set-Buttons $false
    $pb.Value = 0
    $pb.Visibility = [System.Windows.Visibility]::Visible
    Set-Status "Enhancing..." "#8E8E93"
    $timer.Start()
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
    if ($script:proc -and -not $script:proc.HasExited) {
        $t = 0
        if (Test-Path $script:progFile) {
            $line = Get-Content $script:progFile -ErrorAction SilentlyContinue |
                    Where-Object { $_ -like "out_time_ms=*" } | Select-Object -Last 1
            if ($line) { try { $t = [long]($line.Split("=")[1]) / 1000000.0 } catch {} }
        }
        if ($script:totalDur -gt 0 -and $t -gt 0) {
            $frac = [Math]::Min(1.0, $t / $script:totalDur)
            $pb.Value = 100 * $frac
            $tbStatus.Text = ("Enhancing... {0:P0}" -f $frac)
        }
    } elseif ($script:proc) {
        $timer.Stop()
        $pb.Value = 0
        $pb.Visibility = [System.Windows.Visibility]::Collapsed
        Set-Buttons $true
        if ($script:proc.ExitCode -eq 0 -and (Test-Path $script:outPath)) {
            $tbStatus.Text = "Done: $(Split-Path $script:outPath -Leaf)"
            $tbStatus.Foreground = New-Brush "#4ADE80"
        } else {
            $tbStatus.Text = "Enhancement failed (ffmpeg exit $($script:proc.ExitCode))."
            $tbStatus.Foreground = New-Brush "#FF6B6B"
        }
        Refresh-List
        $script:proc = $null
    }
})

$btnEnhance.Add_Click({
    $item = $lv.SelectedItem
    if (-not $item) { $tbStatus.Text = "Select a recording first."; return }
    $script:lastPath = $item.Path
    Start-Enhance $item.Path (Join-Path (Split-Path $item.Path -Parent) "microphone.webm")
})
$btnRefresh.Add_Click({ Refresh-List })
$btnBrowse.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Choose a video or audio file to enhance"
    $dlg.Filter = "Media files (*.mp4;*.webm;*.mkv;*.mov;*.mp3;*.wav;*.m4a;*.aac;*.flac;*.ogg)|*.mp4;*.webm;*.mkv;*.mov;*.mp3;*.wav;*.m4a;*.aac;*.flac;*.ogg|All files (*.*)|*.*"
    $dlg.InitialDirectory = $root
    if ($dlg.ShowDialog() -eq $true) {
        $script:lastPath = $dlg.FileName
        $mic = Join-Path (Split-Path $dlg.FileName -Parent) "microphone.webm"
        Start-Enhance $dlg.FileName $mic
    }
})
$btnOpenFolder.Add_Click({
    $item = $lv.SelectedItem
    if ($item) {
        $script:lastPath = $item.Path
        Show-InExplorer $item.Path
    } elseif ($script:lastPath) {
        Show-InExplorer $script:lastPath
    } else {
        Start-Process explorer.exe $root
    }
})
$btnPlay.Add_Click({
    $item = $lv.SelectedItem
    if ($item) { $script:lastPath = $item.Path }
    if (-not $item -and $script:lastPath) {
        $item = [PSCustomObject]@{ Path = $script:lastPath }
    }
    if (-not $item) { return }
    $enh = Join-Path (Split-Path $item.Path -Parent) ([IO.Path]::GetFileNameWithoutExtension($item.Path) + "-ENHANCED.mp4")
    if (Test-Path $enh) { Start-Process $enh } else { Start-Process $item.Path }
})
$lv.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 2) {
        $item = $lv.SelectedItem
        if ($item) { $script:lastPath = $item.Path; Show-InExplorer $item.Path }
    }
})

if ($SelfTest) { Write-Output "SELFTEST OK - ffmpeg=$ffmpeg"; $window.Close(); return }

Refresh-List
[void]$window.ShowDialog()
