using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("Blacked Aeronautics")]
[assembly: AssemblyProduct("Blacked Aeronautics")]
[assembly: AssemblyCompany("BlackSoul1337")]
[assembly: AssemblyDescription("Запуск и обновление Blacked Aeronautics")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace BlackedAeronauticsUpdater
{
    internal sealed class UpdateConfig
    {
        public string version { get; set; }
        public string repository { get; set; }
        public string launcher { get; set; }
        public string packUrl { get; set; }
        public string packMirrorUrl { get; set; }
    }

    internal sealed class ReleaseInfo
    {
        public string tag_name { get; set; }
        public bool draft { get; set; }
        public bool prerelease { get; set; }
        public List<ReleaseAsset> assets { get; set; }
    }

    internal sealed class ReleaseAsset
    {
        public string name { get; set; }
        public string browser_download_url { get; set; }
        public string digest { get; set; }
        public long size { get; set; }
    }

    internal sealed class DistributionManifest
    {
        public string version { get; set; }
        public List<ManifestEntry> files { get; set; }
    }

    internal sealed class ManifestEntry
    {
        public string path { get; set; }
        public string sha256 { get; set; }
        public string mode { get; set; }
    }

    internal sealed class DownloadDialog : Form
    {
        private readonly ProgressBar progress;
        private readonly Label status;
        private readonly Button cancel;
        private WebClient client;
        private Exception error;
        private bool wasCancelled;

        public DownloadDialog()
        {
            Text = "Обновление Blacked Aeronautics";
            ClientSize = new Size(430, 126);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = true;

            status = new Label();
            status.AutoSize = false;
            status.Location = new Point(18, 18);
            status.Size = new Size(394, 23);
            status.Text = "Загрузка обновления…";

            progress = new ProgressBar();
            progress.Location = new Point(18, 48);
            progress.Size = new Size(394, 22);
            progress.Style = ProgressBarStyle.Continuous;

            cancel = new Button();
            cancel.Location = new Point(312, 84);
            cancel.Size = new Size(100, 28);
            cancel.Text = "Отмена";
            cancel.Click += delegate
            {
                wasCancelled = true;
                cancel.Enabled = false;
                status.Text = "Отмена загрузки…";
                if (client != null)
                    client.CancelAsync();
            };

            Controls.Add(status);
            Controls.Add(progress);
            Controls.Add(cancel);
        }

        public void Download(string url, string destination, string userAgent)
        {
            client = new WebClient();
            client.Headers[HttpRequestHeader.UserAgent] = userAgent;
            client.Headers[HttpRequestHeader.Accept] = "application/octet-stream";
            client.DownloadProgressChanged += OnProgress;
            client.DownloadFileCompleted += OnCompleted;
            client.DownloadFileAsync(new Uri(url), destination);
            ShowDialog();
            client.Dispose();
            client = null;

            if (wasCancelled)
                throw new OperationCanceledException();
            if (error != null)
                throw new InvalidOperationException("Не удалось скачать обновление.", error);
        }

        private void OnProgress(object sender, DownloadProgressChangedEventArgs e)
        {
            progress.Value = Math.Max(0, Math.Min(100, e.ProgressPercentage));
            if (e.TotalBytesToReceive > 0)
            {
                status.Text = string.Format(
                    CultureInfo.CurrentCulture,
                    "Загружено {0:0.0} из {1:0.0} МиБ",
                    e.BytesReceived / 1048576.0,
                    e.TotalBytesToReceive / 1048576.0);
            }
        }

        private void OnCompleted(object sender, AsyncCompletedEventArgs e)
        {
            error = e.Error;
            wasCancelled = wasCancelled || e.Cancelled;
            Close();
        }
    }

    internal static class Program
    {
        private const string ProductName = "Blacked Aeronautics";
        private const string WrapperName = "Blacked Aeronautics.exe";
        private const string ConfigName = "blacked-update.json";
        private const string ManifestName = "distribution-manifest.json";
        private const string ApiBase = "https://api.github.com/repos/";
        private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
        private static string fallbackRoot;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool MoveFileEx(string existingFileName, string newFileName, int flags);

        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;

            try
            {
                if (args.Length > 0 && string.Equals(args[0], "--apply-portable", StringComparison.OrdinalIgnoreCase))
                {
                    ApplyPortable(args);
                    return;
                }
                if (args.Length > 0 && string.Equals(args[0], "--apply-setup", StringComparison.OrdinalIgnoreCase))
                {
                    ApplySetup(args);
                    return;
                }

                RunLauncherFlow(args);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Обновление не удалось. Уже установленная версия не была повреждена.\n\n" + FriendlyError(ex),
                    ProductName,
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);

                string root = string.IsNullOrWhiteSpace(fallbackRoot)
                    ? AppDomain.CurrentDomain.BaseDirectory
                    : fallbackRoot;
                TryLaunch(Path.Combine(root, "elyprismlauncher.exe"), root, null);
                if (args.Length > 0 &&
                    (string.Equals(args[0], "--apply-portable", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(args[0], "--apply-setup", StringComparison.OrdinalIgnoreCase)))
                    ScheduleSelfDelete();
            }
        }

        private static void RunLauncherFlow(string[] args)
        {
            string root = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
            string configPath = Path.Combine(root, ConfigName);
            UpdateConfig config = ReadJson<UpdateConfig>(configPath);
            ValidateConfig(config);
            TryMigratePackwizCommand(root);
            TrySyncLoaderVersion(root, config.packUrl, config.packMirrorUrl);

            List<string> forwarded = new List<string>(args);
            bool skipOnce = forwarded.Remove("--skip-update-once");
            string launcherPath = SafePath(root, config.launcher);

            bool ownsMutex;
            using (Mutex mutex = new Mutex(true, "Local\\BlackedAeronauticsLauncherUpdater", out ownsMutex))
            {
                if (!ownsMutex)
                    return;
                try
                {
                    if (skipOnce || IsLauncherRunning())
                    {
                        Launch(launcherPath, root, forwarded);
                        return;
                    }

                    ReleaseInfo release;
                    try
                    {
                        release = GetLatestRelease(config);
                    }
                    catch
                    {
                        Launch(launcherPath, root, forwarded);
                        return;
                    }

                    string latestVersion = NormalizeVersion(release.tag_name);
                    if (CompareVersions(latestVersion, NormalizeVersion(config.version)) <= 0)
                    {
                        Launch(launcherPath, root, forwarded);
                        return;
                    }

                    DialogResult choice = MessageBox.Show(
                        "Доступна новая версия " + latestVersion + ". Установить её сейчас?\n\n" +
                        "Аккаунты, настройки и файлы сборки сохранятся.",
                        "Обновление Blacked Aeronautics",
                        MessageBoxButtons.YesNo,
                        MessageBoxIcon.Information,
                        MessageBoxDefaultButton.Button1);

                    if (choice != DialogResult.Yes)
                    {
                        Launch(launcherPath, root, forwarded);
                        return;
                    }

                    bool setupInstall = File.Exists(Path.Combine(root, "unins000.exe"));
                    string suffix = setupInstall ? "-win-x64-setup.exe" : "-win-x64-portable.zip";
                    ReleaseAsset asset = FindAsset(release, latestVersion, suffix);
                    ValidateDigest(asset);

                    string workRoot = Path.Combine(Path.GetTempPath(), "Blacked-Aeronautics-Update-" + Guid.NewGuid().ToString("N"));
                    Directory.CreateDirectory(workRoot);
                    string downloadPath = Path.Combine(workRoot, asset.name);

                    using (DownloadDialog dialog = new DownloadDialog())
                        dialog.Download(asset.browser_download_url, downloadPath, UserAgent(config.version));

                    VerifyFile(downloadPath, asset.digest.Substring("sha256:".Length));

                    if (setupInstall)
                    {
                        StartHelper("--apply-setup", downloadPath, root, workRoot);
                        return;
                    }

                    string extractRoot = Path.Combine(workRoot, "extracted");
                    ExtractArchive(downloadPath, extractRoot);
                    string stagedRoot = FindStagedRoot(extractRoot);
                    DistributionManifest manifest = ReadJson<DistributionManifest>(Path.Combine(stagedRoot, ManifestName));
                    ValidateManifest(stagedRoot, manifest, latestVersion);
                    StartHelper("--apply-portable", stagedRoot, root, workRoot);
                }
                finally
                {
                    try { mutex.ReleaseMutex(); }
                    catch (ApplicationException) { }
                }
            }
        }

        private static ReleaseInfo GetLatestRelease(UpdateConfig config)
        {
            string url = ApiBase + config.repository + "/releases/latest";
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
            request.Method = "GET";
            request.Accept = "application/vnd.github+json";
            request.UserAgent = UserAgent(config.version);
            request.Headers["X-GitHub-Api-Version"] = "2022-11-28";
            request.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
            request.Timeout = 10000;
            request.ReadWriteTimeout = 10000;

            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            using (Stream stream = response.GetResponseStream())
            using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
            {
                ReleaseInfo release = Json.Deserialize<ReleaseInfo>(reader.ReadToEnd());
                if (release == null || release.draft || release.prerelease || string.IsNullOrWhiteSpace(release.tag_name))
                    throw new InvalidDataException("GitHub вернул неподходящий Release.");
                return release;
            }
        }

        private static void TrySyncLoaderVersion(string root, params string[] packUrls)
        {
            foreach (string packUrl in packUrls)
            {
                try
                {
                    HttpWebRequest request = (HttpWebRequest)WebRequest.Create(packUrl);
                    request.Method = "GET";
                    request.UserAgent = UserAgent("loader-sync");
                    request.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
                    request.Timeout = 10000;
                    request.ReadWriteTimeout = 10000;

                    string packToml;
                    using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                    using (Stream stream = response.GetResponseStream())
                    using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
                        packToml = reader.ReadToEnd();

                    string neoForgeVersion = ExtractNeoForgeVersion(packToml);
                    string manifestPath = SafePath(
                        root,
                        "instances/Blacked-Aeronautics/mmc-pack.json");
                    UpdateNeoForgeManifest(manifestPath, neoForgeVersion);
                    return;
                }
                catch
                {
                    // Try the next source. A loader check must never block the launcher.
                }
            }
        }

        private static bool TryMigratePackwizCommand(string root)
        {
            try
            {
                string instanceConfig = SafePath(
                    root,
                    "instances/Blacked-Aeronautics/instance.cfg");
                if (!File.Exists(instanceConfig))
                    return false;

                const string legacyCommand =
                    "PreLaunchCommand=\"\\\"$INST_JAVA\\\" -jar packwiz-installer-bootstrap.jar " +
                    "https://blacksoul1337.github.io/Blacked-Aeronautics/pack.toml\"";
                const string mirroredCommand =
                    "PreLaunchCommand=\"powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass " +
                    "-File packwiz-update.ps1 -JavaPath \\\"$INST_JAVA\\\"\"";

                string content = File.ReadAllText(instanceConfig, Encoding.UTF8);
                if (content.IndexOf(legacyCommand, StringComparison.Ordinal) < 0)
                    return false;

                string temporary = instanceConfig + ".update-" + Guid.NewGuid().ToString("N");
                try
                {
                    File.WriteAllText(
                        temporary,
                        content.Replace(legacyCommand, mirroredCommand),
                        new UTF8Encoding(false));
                    File.Copy(temporary, instanceConfig, true);
                }
                finally
                {
                    try
                    {
                        if (File.Exists(temporary))
                            File.Delete(temporary);
                    }
                    catch { }
                }
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static string ExtractNeoForgeVersion(string packToml)
        {
            if (string.IsNullOrWhiteSpace(packToml))
                throw new InvalidDataException("Опубликованный pack.toml пуст.");

            Match section = Regex.Match(
                packToml.Replace("\r\n", "\n"),
                "(?ms)^\\[versions\\]\\s*$\\n(?<body>.*?)(?=^\\[|\\z)",
                RegexOptions.CultureInvariant);
            if (!section.Success)
                throw new InvalidDataException("В pack.toml отсутствует раздел versions.");

            Match version = Regex.Match(
                section.Groups["body"].Value,
                "(?m)^neoforge\\s*=\\s*\"([^\"]+)\"\\s*$",
                RegexOptions.CultureInvariant);
            if (!version.Success ||
                !Regex.IsMatch(version.Groups[1].Value, "^[0-9]+\\.[0-9]+\\.[0-9A-Za-z.+-]+$", RegexOptions.CultureInvariant))
                throw new InvalidDataException("В pack.toml указана неверная версия NeoForge.");
            return version.Groups[1].Value;
        }

        private static bool UpdateNeoForgeManifest(string manifestPath, string version)
        {
            if (!File.Exists(manifestPath))
                return false;

            Dictionary<string, object> document =
                Json.DeserializeObject(File.ReadAllText(manifestPath, Encoding.UTF8)) as Dictionary<string, object>;
            if (document == null || !document.ContainsKey("components"))
                throw new InvalidDataException("Не удалось прочитать компоненты инстанса.");

            object[] components = document["components"] as object[];
            if (components == null)
                throw new InvalidDataException("Не удалось прочитать компоненты инстанса.");

            Dictionary<string, object> neoForge = null;
            foreach (object item in components)
            {
                Dictionary<string, object> component = item as Dictionary<string, object>;
                if (component != null && component.ContainsKey("uid") &&
                    string.Equals(Convert.ToString(component["uid"], CultureInfo.InvariantCulture), "net.neoforged", StringComparison.Ordinal))
                {
                    neoForge = component;
                    break;
                }
            }
            if (neoForge == null)
                throw new InvalidDataException("В инстансе отсутствует компонент NeoForge.");

            string current = neoForge.ContainsKey("version")
                ? Convert.ToString(neoForge["version"], CultureInfo.InvariantCulture)
                : string.Empty;
            if (string.Equals(current, version, StringComparison.Ordinal))
                return false;

            neoForge["version"] = version;
            if (neoForge.ContainsKey("cachedVersion"))
                neoForge["cachedVersion"] = version;

            string temporary = manifestPath + ".update-" + Guid.NewGuid().ToString("N");
            try
            {
                File.WriteAllText(temporary, Json.Serialize(document), new UTF8Encoding(false));
                File.Copy(temporary, manifestPath, true);
            }
            finally
            {
                try
                {
                    if (File.Exists(temporary))
                        File.Delete(temporary);
                }
                catch { }
            }
            return true;
        }

        private static ReleaseAsset FindAsset(ReleaseInfo release, string version, string suffix)
        {
            string expected = "Blacked-Aeronautics-" + version + suffix;
            if (release.assets != null)
            {
                foreach (ReleaseAsset asset in release.assets)
                {
                    if (asset != null && string.Equals(asset.name, expected, StringComparison.OrdinalIgnoreCase))
                        return asset;
                }
            }
            throw new InvalidDataException("В новом Release пока нет подходящего файла для Windows x64.");
        }

        private static void ValidateDigest(ReleaseAsset asset)
        {
            if (asset == null || string.IsNullOrWhiteSpace(asset.browser_download_url))
                throw new InvalidDataException("У файла обновления нет адреса загрузки.");
            if (string.IsNullOrWhiteSpace(asset.digest) ||
                !Regex.IsMatch(asset.digest, "^sha256:[0-9a-fA-F]{64}$", RegexOptions.CultureInvariant))
                throw new InvalidDataException("GitHub не предоставил контрольную сумму обновления.");
        }

        private static void StartHelper(string mode, string payload, string root, string workRoot)
        {
            string helper = Path.Combine(Path.GetTempPath(), "Blacked-Aeronautics-Updater-" + Guid.NewGuid().ToString("N") + ".exe");
            File.Copy(Application.ExecutablePath, helper, true);

            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = helper;
            start.Arguments = string.Join(" ", new[]
            {
                Quote(mode),
                Quote(payload),
                Quote(root),
                Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture),
                Quote(workRoot)
            });
            start.WorkingDirectory = Path.GetTempPath();
            start.UseShellExecute = true;
            Process.Start(start);
        }

        private static void ApplySetup(string[] args)
        {
            if (args.Length != 5)
                throw new ArgumentException("Неверные параметры обновления Setup.");

            string setupPath = Path.GetFullPath(args[1]);
            string targetRoot = Path.GetFullPath(args[2]);
            fallbackRoot = targetRoot;
            int parentPid = int.Parse(args[3], CultureInfo.InvariantCulture);
            string workRoot = Path.GetFullPath(args[4]);
            WaitForProcess(parentPid);

            ProcessStartInfo install = new ProcessStartInfo();
            install.FileName = setupPath;
            install.Arguments = "/VERYSILENT /SUPPRESSMSGBOXES /CLOSEAPPLICATIONS /NORESTART /DIR=" + Quote(targetRoot);
            install.WorkingDirectory = Path.GetDirectoryName(setupPath);
            install.UseShellExecute = true;
            Process process = Process.Start(install);
            process.WaitForExit();

            if (process.ExitCode != 0)
                throw new InvalidOperationException("Установщик завершился с ошибкой.");

            CleanupWorkDirectory(workRoot);
            RelaunchWrapper(targetRoot);
            ScheduleSelfDelete();
        }

        private static void ApplyPortable(string[] args)
        {
            if (args.Length != 5)
                throw new ArgumentException("Неверные параметры обновления Portable.");

            string stagedRoot = Path.GetFullPath(args[1]);
            string targetRoot = Path.GetFullPath(args[2]);
            fallbackRoot = targetRoot;
            int parentPid = int.Parse(args[3], CultureInfo.InvariantCulture);
            string workRoot = Path.GetFullPath(args[4]);
            WaitForProcess(parentPid);

            DistributionManifest next = ReadJson<DistributionManifest>(Path.Combine(stagedRoot, ManifestName));
            ValidateManifest(stagedRoot, next, NormalizeVersion(next.version));

            DistributionManifest previous = null;
            string currentManifestPath = Path.Combine(targetRoot, ManifestName);
            if (File.Exists(currentManifestPath))
            {
                try { previous = ReadJson<DistributionManifest>(currentManifestPath); }
                catch { previous = null; }
            }

            string backupRoot = Path.Combine(Path.GetTempPath(), "Blacked-Aeronautics-Backup-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(backupRoot);
            Dictionary<string, string> backups = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            HashSet<string> created = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            try
            {
                Dictionary<string, ManifestEntry> nextFiles = IndexManifest(next);
                if (previous != null && previous.files != null)
                {
                    foreach (ManifestEntry oldEntry in previous.files)
                    {
                        if (oldEntry == null || !string.Equals(oldEntry.mode, "replace", StringComparison.OrdinalIgnoreCase))
                            continue;
                        string relative = NormalizeRelative(oldEntry.path);
                        if (nextFiles.ContainsKey(relative))
                            continue;
                        string destination = SafePath(targetRoot, relative);
                        Backup(destination, relative, backupRoot, backups, created);
                        if (File.Exists(destination))
                            File.Delete(destination);
                    }
                }

                foreach (ManifestEntry entry in next.files)
                {
                    string relative = NormalizeRelative(entry.path);
                    string source = SafePath(stagedRoot, relative);
                    string destination = SafePath(targetRoot, relative);
                    bool seed = string.Equals(entry.mode, "seed", StringComparison.OrdinalIgnoreCase);
                    if (seed && File.Exists(destination))
                        continue;

                    Backup(destination, relative, backupRoot, backups, created);
                    string destinationDirectory = Path.GetDirectoryName(destination);
                    if (!Directory.Exists(destinationDirectory))
                        Directory.CreateDirectory(destinationDirectory);
                    File.Copy(source, destination, true);
                }

                Backup(currentManifestPath, ManifestName, backupRoot, backups, created);
                File.Copy(Path.Combine(stagedRoot, ManifestName), currentManifestPath, true);
            }
            catch
            {
                Rollback(targetRoot, backups, created);
                throw;
            }
            finally
            {
                TryDeleteDirectory(backupRoot);
            }

            CleanupWorkDirectory(workRoot);
            RelaunchWrapper(targetRoot);
            ScheduleSelfDelete();
        }

        private static void Backup(
            string destination,
            string relative,
            string backupRoot,
            Dictionary<string, string> backups,
            HashSet<string> created)
        {
            if (backups.ContainsKey(relative) || created.Contains(relative))
                return;

            if (!File.Exists(destination))
            {
                created.Add(relative);
                return;
            }

            string backup = SafePath(backupRoot, relative);
            string backupDirectory = Path.GetDirectoryName(backup);
            if (!Directory.Exists(backupDirectory))
                Directory.CreateDirectory(backupDirectory);
            File.Copy(destination, backup, true);
            backups[relative] = backup;
        }

        private static void Rollback(
            string targetRoot,
            Dictionary<string, string> backups,
            HashSet<string> created)
        {
            foreach (string relative in created)
            {
                try
                {
                    string destination = SafePath(targetRoot, relative);
                    if (File.Exists(destination))
                        File.Delete(destination);
                }
                catch { }
            }

            foreach (KeyValuePair<string, string> item in backups)
            {
                try
                {
                    string destination = SafePath(targetRoot, item.Key);
                    string directory = Path.GetDirectoryName(destination);
                    if (!Directory.Exists(directory))
                        Directory.CreateDirectory(directory);
                    File.Copy(item.Value, destination, true);
                }
                catch { }
            }
        }

        private static void ValidateManifest(string stagedRoot, DistributionManifest manifest, string expectedVersion)
        {
            if (manifest == null || manifest.files == null ||
                !string.Equals(NormalizeVersion(manifest.version), NormalizeVersion(expectedVersion), StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("В архиве находится неверная версия обновления.");

            Dictionary<string, ManifestEntry> indexed = IndexManifest(manifest);
            foreach (KeyValuePair<string, ManifestEntry> item in indexed)
            {
                ManifestEntry entry = item.Value;
                if (!string.Equals(entry.mode, "replace", StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(entry.mode, "seed", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("В манифесте указан неизвестный режим файла.");
                if (string.IsNullOrWhiteSpace(entry.sha256) ||
                    !Regex.IsMatch(entry.sha256, "^[0-9a-fA-F]{64}$", RegexOptions.CultureInvariant))
                    throw new InvalidDataException("В манифесте указана неверная контрольная сумма.");
                VerifyFile(SafePath(stagedRoot, item.Key), entry.sha256);
            }
        }

        private static Dictionary<string, ManifestEntry> IndexManifest(DistributionManifest manifest)
        {
            Dictionary<string, ManifestEntry> result = new Dictionary<string, ManifestEntry>(StringComparer.OrdinalIgnoreCase);
            if (manifest == null || manifest.files == null)
                return result;
            foreach (ManifestEntry entry in manifest.files)
            {
                if (entry == null)
                    throw new InvalidDataException("В манифесте есть пустая запись.");
                string relative = NormalizeRelative(entry.path);
                if (string.Equals(relative, ManifestName, StringComparison.OrdinalIgnoreCase) || result.ContainsKey(relative))
                    throw new InvalidDataException("В манифесте есть повторяющийся или запрещённый путь.");
                result.Add(relative, entry);
            }
            return result;
        }

        private static void ExtractArchive(string archivePath, string destinationRoot)
        {
            Directory.CreateDirectory(destinationRoot);
            using (ZipArchive archive = ZipFile.OpenRead(archivePath))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string relative = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    if (string.IsNullOrWhiteSpace(relative))
                        continue;
                    bool directoryEntry = entry.FullName.EndsWith("/", StringComparison.Ordinal);
                    if (directoryEntry)
                        relative = relative.TrimEnd(Path.DirectorySeparatorChar);
                    string destination = SafePath(destinationRoot, relative);
                    if (directoryEntry)
                    {
                        Directory.CreateDirectory(destination);
                        continue;
                    }
                    string directory = Path.GetDirectoryName(destination);
                    if (!Directory.Exists(directory))
                        Directory.CreateDirectory(directory);
                    using (Stream input = entry.Open())
                    using (FileStream output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        input.CopyTo(output);
                }
            }
        }

        private static string FindStagedRoot(string extractRoot)
        {
            string[] manifests = Directory.GetFiles(extractRoot, ManifestName, SearchOption.AllDirectories);
            if (manifests.Length != 1)
                throw new InvalidDataException("Архив обновления имеет неверную структуру.");
            return Path.GetDirectoryName(manifests[0]);
        }

        private static void VerifyFile(string path, string expectedHash)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("В обновлении отсутствует необходимый файл.", path);
            string actual;
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
                actual = ToHex(sha.ComputeHash(stream));
            if (!string.Equals(actual, expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Контрольная сумма обновления не совпала.");
        }

        private static string ToHex(byte[] bytes)
        {
            StringBuilder result = new StringBuilder(bytes.Length * 2);
            foreach (byte value in bytes)
                result.Append(value.ToString("x2", CultureInfo.InvariantCulture));
            return result.ToString();
        }

        private static T ReadJson<T>(string path)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("Не найден файл настроек обновления.", path);
            T value = Json.Deserialize<T>(File.ReadAllText(path, Encoding.UTF8));
            if (value == null)
                throw new InvalidDataException("Не удалось прочитать настройки обновления.");
            return value;
        }

        private static void ValidateConfig(UpdateConfig config)
        {
            if (config == null || string.IsNullOrWhiteSpace(config.version) ||
                string.IsNullOrWhiteSpace(config.repository) || string.IsNullOrWhiteSpace(config.launcher) ||
                string.IsNullOrWhiteSpace(config.packUrl) || string.IsNullOrWhiteSpace(config.packMirrorUrl) ||
                !Regex.IsMatch(config.repository, "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", RegexOptions.CultureInvariant))
                throw new InvalidDataException("Настройки обновления повреждены.");
            ValidatePackUrl(config.packUrl, "blacksoul1337.github.io");
            ValidatePackUrl(config.packMirrorUrl, "cdn.jsdelivr.net");
            SafePath(AppDomain.CurrentDomain.BaseDirectory, config.launcher);
        }

        private static void ValidatePackUrl(string value, string expectedHost)
        {
            Uri parsed;
            if (!Uri.TryCreate(value, UriKind.Absolute, out parsed) ||
                parsed.Scheme != Uri.UriSchemeHttps ||
                !string.Equals(parsed.Host, expectedHost, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Адрес обновления сборки повреждён.");
        }

        private static int CompareVersions(string left, string right)
        {
            List<string> a = VersionParts(left);
            List<string> b = VersionParts(right);
            int count = Math.Max(a.Count, b.Count);
            for (int i = 0; i < count; i++)
            {
                string av = i < a.Count ? a[i] : "0";
                string bv = i < b.Count ? b[i] : "0";
                long an;
                long bn;
                bool aNumber = long.TryParse(av, NumberStyles.None, CultureInfo.InvariantCulture, out an);
                bool bNumber = long.TryParse(bv, NumberStyles.None, CultureInfo.InvariantCulture, out bn);
                int comparison;
                if (aNumber && bNumber)
                    comparison = an.CompareTo(bn);
                else if (aNumber != bNumber)
                    comparison = aNumber ? 1 : -1;
                else
                    comparison = string.Compare(av, bv, StringComparison.OrdinalIgnoreCase);
                if (comparison != 0)
                    return comparison;
            }
            return 0;
        }

        private static List<string> VersionParts(string version)
        {
            List<string> result = new List<string>();
            foreach (Match match in Regex.Matches(NormalizeVersion(version), "[0-9]+|[A-Za-z]+", RegexOptions.CultureInvariant))
                result.Add(match.Value);
            return result;
        }

        private static string NormalizeVersion(string version)
        {
            if (string.IsNullOrWhiteSpace(version))
                return string.Empty;
            string value = version.Trim();
            if (value.StartsWith("v", StringComparison.OrdinalIgnoreCase))
                value = value.Substring(1);
            return value;
        }

        private static string NormalizeRelative(string relative)
        {
            if (string.IsNullOrWhiteSpace(relative) || Path.IsPathRooted(relative))
                throw new InvalidDataException("В обновлении найден небезопасный путь.");
            string value = relative.Replace('/', Path.DirectorySeparatorChar).TrimStart(Path.DirectorySeparatorChar);
            string[] parts = value.Split(Path.DirectorySeparatorChar);
            foreach (string part in parts)
            {
                if (string.IsNullOrWhiteSpace(part) || part == "." || part == ".." || part.IndexOf(':') >= 0)
                    throw new InvalidDataException("В обновлении найден небезопасный путь.");
            }
            return string.Join(Path.DirectorySeparatorChar.ToString(), parts);
        }

        private static string SafePath(string root, string relative)
        {
            string rootPath = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string relativePath = NormalizeRelative(relative);
            string candidate = Path.GetFullPath(Path.Combine(rootPath, relativePath));
            string prefix = rootPath + Path.DirectorySeparatorChar;
            if (!candidate.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("В обновлении найден небезопасный путь.");
            return candidate;
        }

        private static void WaitForProcess(int processId)
        {
            try
            {
                Process process = Process.GetProcessById(processId);
                process.WaitForExit(30000);
            }
            catch (ArgumentException) { }
        }

        private static bool IsLauncherRunning()
        {
            return Process.GetProcessesByName("elyprismlauncher").Length > 0;
        }

        private static void RelaunchWrapper(string root)
        {
            TryLaunch(Path.Combine(root, WrapperName), root, "--skip-update-once");
        }

        private static void Launch(string executable, string workingDirectory, IList<string> arguments)
        {
            string joined = null;
            if (arguments != null && arguments.Count > 0)
            {
                List<string> quoted = new List<string>();
                foreach (string argument in arguments)
                    quoted.Add(Quote(argument));
                joined = string.Join(" ", quoted.ToArray());
            }
            if (!TryLaunch(executable, workingDirectory, joined))
                throw new FileNotFoundException("Не удалось открыть лаунчер.", executable);
        }

        private static bool TryLaunch(string executable, string workingDirectory, string arguments)
        {
            try
            {
                if (!File.Exists(executable))
                    return false;
                ProcessStartInfo start = new ProcessStartInfo();
                start.FileName = executable;
                start.WorkingDirectory = workingDirectory;
                start.UseShellExecute = true;
                if (!string.IsNullOrWhiteSpace(arguments))
                    start.Arguments = arguments;
                Process.Start(start);
                return true;
            }
            catch { return false; }
        }

        private static string Quote(string value)
        {
            if (value == null)
                return "\"\"";
            StringBuilder result = new StringBuilder();
            result.Append('\"');
            int backslashes = 0;
            foreach (char character in value)
            {
                if (character == '\\')
                {
                    backslashes++;
                    continue;
                }
                if (character == '\"')
                {
                    result.Append('\\', backslashes * 2 + 1);
                    result.Append('\"');
                    backslashes = 0;
                    continue;
                }
                result.Append('\\', backslashes);
                backslashes = 0;
                result.Append(character);
            }
            result.Append('\\', backslashes * 2);
            result.Append('\"');
            return result.ToString();
        }

        private static string UserAgent(string version)
        {
            return "Blacked-Aeronautics-Updater/" + NormalizeVersion(version);
        }

        private static string FriendlyError(Exception error)
        {
            if (error is OperationCanceledException)
                return "Загрузка была отменена.";
            return string.IsNullOrWhiteSpace(error.Message) ? "Попробуйте ещё раз позже." : error.Message;
        }

        private static void CleanupWorkDirectory(string path)
        {
            TryDeleteDirectory(path);
        }

        private static void TryDeleteDirectory(string path)
        {
            try
            {
                if (Directory.Exists(path))
                    Directory.Delete(path, true);
            }
            catch { }
        }

        private static void ScheduleSelfDelete()
        {
            try { MoveFileEx(Application.ExecutablePath, null, 4); }
            catch { }
        }
    }
}
