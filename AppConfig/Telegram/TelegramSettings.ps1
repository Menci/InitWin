if (-not ('InitWin.Telegram.SettingsFile' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace InitWin.Telegram {
    internal enum ItemKind {
        Int32,
        UInt32,
        Int64,
        UInt64,
        UInt16,
        UInt8,
        String,
        ByteArray,
        StringStringMap,
        Int64List,
        UInt64List,
        RecentEmojiList,
        EmojiVariantList,
        StringList,
        ByteArrayMap
    }

    internal enum PublicKind {
        BoolInt32,
        Int32,
        UInt32,
        UInt16,
        String,
        EnumInt32,
        SendFilesWay
    }

    internal sealed class FieldSpec {
        public readonly string Name;
        public readonly PublicKind Kind;
        public readonly Dictionary<int, string> EnumNames;

        public FieldSpec(string name, PublicKind kind) : this(name, kind, null) {
        }

        public FieldSpec(string name, PublicKind kind, Dictionary<int, string> enumNames) {
            Name = name;
            Kind = kind;
            EnumNames = enumNames;
        }
    }

    internal sealed class SettingItem {
        public readonly string Name;
        public readonly ItemKind Kind;
        public object Value;

        public SettingItem(string name, ItemKind kind, object value) {
            Name = name;
            Kind = kind;
            Value = value;
        }
    }

    internal sealed class StringStringPair {
        public string Key;
        public string Value;
    }

    internal sealed class RecentEmojiItem {
        public string Id;
        public ushort Rating;
    }

    internal sealed class EmojiVariantItem {
        public string Id;
        public byte Variant;
    }

    internal sealed class ByteArrayPair {
        public byte[] Key;
        public byte[] Value;
    }

    internal sealed class SettingsBlock {
        public uint Id;
        public byte[] RawPayload;
        public CoreSettings ApplicationSettings;
    }

    internal sealed class QtReader {
        private readonly byte[] _data;
        private int _position;

        public QtReader(byte[] data) {
            _data = data;
        }

        public int Position { get { return _position; } }
        public bool End { get { return _position >= _data.Length; } }

        public byte[] ReadRemaining() {
            var result = Slice(_data, _position, _data.Length - _position);
            _position = _data.Length;
            return result;
        }

        public byte[] Slice(int start, int length) {
            return Slice(_data, start, length);
        }

        public byte ReadUInt8() {
            Require(1);
            return _data[_position++];
        }

        public ushort ReadUInt16() {
            Require(2);
            var result = (ushort)((_data[_position] << 8) | _data[_position + 1]);
            _position += 2;
            return result;
        }

        public int ReadInt32() {
            return unchecked((int)ReadUInt32());
        }

        public uint ReadUInt32() {
            Require(4);
            var result = ((uint)_data[_position] << 24)
                | ((uint)_data[_position + 1] << 16)
                | ((uint)_data[_position + 2] << 8)
                | _data[_position + 3];
            _position += 4;
            return result;
        }

        public long ReadInt64() {
            return unchecked((long)ReadUInt64());
        }

        public ulong ReadUInt64() {
            Require(8);
            ulong result = 0;
            for (var i = 0; i != 8; ++i) {
                result = (result << 8) | _data[_position + i];
            }
            _position += 8;
            return result;
        }

        public string ReadString() {
            var length = ReadUInt32();
            if (length == 0xFFFFFFFFU) {
                return null;
            }
            if ((length & 1) != 0) {
                throw new InvalidDataException("Invalid Qt QString byte length: " + length);
            }
            if (length > int.MaxValue) {
                throw new InvalidDataException("Qt QString is too large: " + length);
            }
            Require((int)length);
            var result = Encoding.BigEndianUnicode.GetString(_data, _position, (int)length);
            _position += (int)length;
            return result;
        }

        public byte[] ReadByteArray() {
            var length = ReadUInt32();
            if (length == 0xFFFFFFFFU) {
                return null;
            }
            if (length > int.MaxValue) {
                throw new InvalidDataException("Qt QByteArray is too large: " + length);
            }
            Require((int)length);
            var result = Slice(_data, _position, (int)length);
            _position += (int)length;
            return result;
        }

        private void Require(int count) {
            if (count < 0 || _position + count > _data.Length) {
                throw new EndOfStreamException("Unexpected end of Telegram settings data.");
            }
        }

        private static byte[] Slice(byte[] source, int start, int length) {
            var result = new byte[length];
            Buffer.BlockCopy(source, start, result, 0, length);
            return result;
        }
    }

    internal sealed class QtWriter {
        private readonly MemoryStream _stream = new MemoryStream();

        public byte[] ToArray() {
            return _stream.ToArray();
        }

        public void WriteRaw(byte[] value) {
            if (value != null && value.Length != 0) {
                _stream.Write(value, 0, value.Length);
            }
        }

        public void WriteUInt8(byte value) {
            _stream.WriteByte(value);
        }

        public void WriteUInt16(ushort value) {
            _stream.WriteByte((byte)(value >> 8));
            _stream.WriteByte((byte)value);
        }

        public void WriteInt32(int value) {
            WriteUInt32(unchecked((uint)value));
        }

        public void WriteUInt32(uint value) {
            _stream.WriteByte((byte)(value >> 24));
            _stream.WriteByte((byte)(value >> 16));
            _stream.WriteByte((byte)(value >> 8));
            _stream.WriteByte((byte)value);
        }

        public void WriteInt64(long value) {
            WriteUInt64(unchecked((ulong)value));
        }

        public void WriteUInt64(ulong value) {
            for (var i = 7; i >= 0; --i) {
                _stream.WriteByte((byte)(value >> (8 * i)));
            }
        }

        public void WriteString(string value) {
            if (value == null) {
                WriteUInt32(0xFFFFFFFFU);
                return;
            }
            var bytes = Encoding.BigEndianUnicode.GetBytes(value);
            WriteUInt32((uint)bytes.Length);
            WriteRaw(bytes);
        }

        public void WriteByteArray(byte[] value) {
            if (value == null) {
                WriteUInt32(0xFFFFFFFFU);
                return;
            }
            WriteUInt32((uint)value.Length);
            WriteRaw(value);
        }
    }

    internal sealed class CoreSettings {
        private readonly List<SettingItem> _items = new List<SettingItem>();
        private readonly Dictionary<string, SettingItem> _byName = new Dictionary<string, SettingItem>(StringComparer.Ordinal);
        private byte[] _trailingBytes = new byte[0];

        public static CoreSettings Parse(byte[] bytes) {
            var reader = new QtReader(bytes);
            var settings = new CoreSettings();

            settings.Add("ThemesAccentColors", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("AdaptiveForWide", ItemKind.Int32, reader.ReadInt32());
            settings.Add("ModerateModeEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SongVolume", ItemKind.Int32, reader.ReadInt32());
            settings.Add("VideoVolume", ItemKind.Int32, reader.ReadInt32());
            settings.Add("AskDownloadPath", ItemKind.Int32, reader.ReadInt32());
            settings.Add("DownloadPath", ItemKind.String, reader.ReadString());
            settings.Add("DownloadPathBookmark", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("NonDefaultVoicePlaybackSpeed", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SoundNotify", ItemKind.Int32, reader.ReadInt32());
            settings.Add("DesktopNotify", ItemKind.Int32, reader.ReadInt32());
            settings.Add("FlashBounceNotify", ItemKind.Int32, reader.ReadInt32());
            settings.Add("NotifyView", ItemKind.Int32, reader.ReadInt32());
            settings.Add("NativeNotifications", ItemKind.Int32, reader.ReadInt32());
            settings.Add("NotificationsCount", ItemKind.Int32, reader.ReadInt32());
            settings.Add("NotificationsCorner", ItemKind.Int32, reader.ReadInt32());
            settings.Add("AutoLock", ItemKind.Int32, reader.ReadInt32());
            settings.Add("LegacyCallPlaybackDeviceId", ItemKind.String, reader.ReadString());
            settings.Add("LegacyCallCaptureDeviceId", ItemKind.String, reader.ReadString());
            settings.Add("CallOutputVolume", ItemKind.Int32, reader.ReadInt32());
            settings.Add("CallInputVolume", ItemKind.Int32, reader.ReadInt32());
            settings.Add("CallAudioDuckingEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("LastSeenWarningSeen", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SoundOverrides", ItemKind.StringStringMap, ReadStringStringMap(reader));
            settings.Add("SendFilesWay", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SendSubmitWay", ItemKind.Int32, reader.ReadInt32());
            settings.Add("IncludeMutedCounter", ItemKind.Int32, reader.ReadInt32());
            settings.Add("CountUnreadMessages", ItemKind.Int32, reader.ReadInt32());
            settings.Add("LegacyExeLaunchWarning", ItemKind.Int32, reader.ReadInt32());
            settings.Add("NotifyAboutPinned", ItemKind.Int32, reader.ReadInt32());
            settings.Add("LoopAnimatedStickers", ItemKind.Int32, reader.ReadInt32());
            settings.Add("LargeEmoji", ItemKind.Int32, reader.ReadInt32());
            settings.Add("ReplaceEmoji", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SuggestEmoji", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SuggestStickersByEmoji", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SpellcheckerEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("VideoPlaybackSpeed", ItemKind.Int32, reader.ReadInt32());
            settings.Add("VideoPipGeometry", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("DictionariesEnabled", ItemKind.Int64List, ReadInt64List(reader));
            settings.Add("AutoDownloadDictionaries", ItemKind.Int32, reader.ReadInt32());
            settings.Add("MainMenuAccountsShown", ItemKind.Int32, reader.ReadInt32());
            settings.Add("TabbedSelectorSectionEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("FloatPlayerColumn", ItemKind.Int32, reader.ReadInt32());
            settings.Add("FloatPlayerCorner", ItemKind.Int32, reader.ReadInt32());
            settings.Add("ThirdSectionInfoEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("DialogsWithChatWidthRatio", ItemKind.Int32, reader.ReadInt32());
            settings.Add("ThirdColumnWidth", ItemKind.Int32, reader.ReadInt32());
            settings.Add("ThirdSectionExtendedBy", ItemKind.Int32, reader.ReadInt32());
            settings.Add("NotifyFromAll", ItemKind.Int32, reader.ReadInt32());
            settings.Add("NativeWindowFrame", ItemKind.Int32, reader.ReadInt32());
            settings.Add("LegacySystemDarkMode", ItemKind.Int32, reader.ReadInt32());
            settings.Add("CameraDeviceId", ItemKind.String, reader.ReadString());
            settings.Add("IpRevealWarning", ItemKind.Int32, reader.ReadInt32());
            settings.Add("GroupCallPushToTalk", ItemKind.Int32, reader.ReadInt32());
            settings.Add("GroupCallPushToTalkShortcut", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("GroupCallPushToTalkDelay", ItemKind.Int64, reader.ReadInt64());
            settings.Add("LegacyCallAudioBackend", ItemKind.Int32, reader.ReadInt32());
            settings.Add("DisableCallsLegacy", ItemKind.Int32, reader.ReadInt32());
            settings.Add("WindowPosition", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("RecentEmojiPreload", ItemKind.RecentEmojiList, ReadRecentEmojiList(reader));
            settings.Add("EmojiVariants", ItemKind.EmojiVariantList, ReadEmojiVariantList(reader));
            settings.Add("OldDisableOpenGL", ItemKind.Int32, reader.ReadInt32());
            settings.Add("OldNoiseSuppression", ItemKind.Int32, reader.ReadInt32());
            settings.Add("WorkMode", ItemKind.Int32, reader.ReadInt32());
            settings.Add("Proxy", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("HiddenGroupCallTooltips", ItemKind.Int32, reader.ReadInt32());
            settings.Add("DisableOpenGL", ItemKind.Int32, reader.ReadInt32());
            settings.Add("PhotoEditorBrush", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("GroupCallNoiseSuppression", ItemKind.Int32, reader.ReadInt32());
            settings.Add("VoicePlaybackSpeed", ItemKind.Int32, reader.ReadInt32());
            settings.Add("CloseBehavior", ItemKind.Int32, reader.ReadInt32());
            settings.Add("CustomDeviceModel", ItemKind.String, reader.ReadString());
            settings.Add("PlayerRepeatMode", ItemKind.Int32, reader.ReadInt32());
            settings.Add("PlayerOrderMode", ItemKind.Int32, reader.ReadInt32());
            settings.Add("MacWarnBeforeQuit", ItemKind.Int32, reader.ReadInt32());
            settings.Add("AccountsOrder", ItemKind.UInt64List, ReadUInt64List(reader));
            settings.Add("OldHardwareAcceleratedVideo", ItemKind.Int32, reader.ReadInt32());
            settings.Add("ChatQuickAction", ItemKind.Int32, reader.ReadInt32());
            settings.Add("HardwareAcceleratedVideo", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SuggestAnimatedEmoji", ItemKind.Int32, reader.ReadInt32());
            settings.Add("CornerReaction", ItemKind.Int32, reader.ReadInt32());
            settings.Add("TranslateButtonEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SkipTranslationLanguages", ItemKind.UInt64List, ReadUInt64List(reader));
            settings.Add("RememberedDeleteMessageOnlyForYou", ItemKind.Int32, reader.ReadInt32());
            settings.Add("TranslateChatEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("TranslateToRaw", ItemKind.UInt64, reader.ReadUInt64());
            settings.Add("WindowTitleHideChatName", ItemKind.Int32, reader.ReadInt32());
            settings.Add("WindowTitleHideAccountName", ItemKind.Int32, reader.ReadInt32());
            settings.Add("WindowTitleHideTotalUnread", ItemKind.Int32, reader.ReadInt32());
            settings.Add("MediaViewPosition", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("IgnoreBatterySaving", ItemKind.Int32, reader.ReadInt32());
            settings.Add("MacRoundIconDigest", ItemKind.UInt64, reader.ReadUInt64());
            settings.Add("StoriesClickTooltipHidden", ItemKind.Int32, reader.ReadInt32());
            settings.Add("RecentEmojiSkip", ItemKind.StringList, ReadStringList(reader));
            settings.Add("TrayIconMonochrome", ItemKind.Int32, reader.ReadInt32());
            settings.Add("TtlVoiceClickTooltipHidden", ItemKind.Int32, reader.ReadInt32());
            settings.Add("PlaybackDeviceId", ItemKind.String, reader.ReadString());
            settings.Add("CaptureDeviceId", ItemKind.String, reader.ReadString());
            settings.Add("CallPlaybackDeviceId", ItemKind.String, reader.ReadString());
            settings.Add("CallCaptureDeviceId", ItemKind.String, reader.ReadString());
            settings.Add("IvPosition", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("NoWarningExtensions", ItemKind.String, reader.ReadString());
            settings.Add("CustomFontFamily", ItemKind.String, reader.ReadString());
            settings.Add("DialogsNoChatWidthRatio", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SystemUnlockEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("WeatherInCelsius", ItemKind.Int32, reader.ReadInt32());
            settings.Add("TonsiteStorageToken", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("IncludeMutedCounterFolders", ItemKind.Int32, reader.ReadInt32());
            settings.Add("ChatFiltersHorizontal", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SkipToastsInFocus", ItemKind.Int32, reader.ReadInt32());
            settings.Add("RecordVideoMessages", ItemKind.Int32, reader.ReadInt32());
            settings.Add("VideoQuality", ItemKind.UInt32, reader.ReadUInt32());
            settings.Add("IvZoom", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SystemDarkModeEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("QuickDialogAction", ItemKind.Int32, reader.ReadInt32());
            settings.Add("NotificationsVolume", ItemKind.UInt16, reader.ReadUInt16());
            settings.Add("NotificationsDisplayChecksum", ItemKind.Int32, reader.ReadInt32());
            settings.Add("CallPanelPosition", ItemKind.ByteArray, reader.ReadByteArray());
            settings.Add("CornerReply", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SystemAccentColorEnabled", ItemKind.Int32, reader.ReadInt32());
            settings.Add("UsePlatformTranslation", ItemKind.Int32, reader.ReadInt32());
            settings.Add("SystemTextReplace", ItemKind.Int32, reader.ReadInt32());
            settings.Add("Preferences", ItemKind.ByteArrayMap, ReadByteArrayMap(reader));
            settings.Add("AudioPlaybackSpeed", ItemKind.Int32, reader.ReadInt32());
            settings._trailingBytes = reader.ReadRemaining();

            return settings;
        }

        public byte[] Serialize() {
            var writer = new QtWriter();
            foreach (var item in _items) {
                WriteItem(writer, item);
            }
            writer.WriteRaw(_trailingBytes);
            return writer.ToArray();
        }

        public object GetPublicValue(string name) {
            var spec = SettingsFile.GetFieldSpec(name);
            var item = GetItem(name);
            return ConvertRawToPublic(spec, item.Value);
        }

        public object NormalizeFieldOverride(string name, object value) {
            var spec = SettingsFile.GetFieldSpec(name);
            return ConvertPublicToRaw(spec, value);
        }

        public bool FieldEquals(string name, object rawValue) {
            return ObjectEquals(GetItem(name).Value, rawValue);
        }

        public void SetFieldRaw(string name, object rawValue) {
            GetItem(name).Value = rawValue;
        }

        public byte[] GetPreference(byte[] key) {
            var preferences = (List<ByteArrayPair>)GetItem("Preferences").Value;
            foreach (var pair in preferences) {
                if (ByteArrayEquals(pair.Key, key)) {
                    return pair.Value;
                }
            }
            return null;
        }

        public void SetPreference(byte[] key, byte[] value) {
            var preferences = (List<ByteArrayPair>)GetItem("Preferences").Value;
            foreach (var pair in preferences) {
                if (ByteArrayEquals(pair.Key, key)) {
                    pair.Value = value;
                    return;
                }
            }
            preferences.Add(new ByteArrayPair { Key = key, Value = value });
        }

        internal SettingItem GetItem(string name) {
            SettingItem item;
            if (!_byName.TryGetValue(name, out item)) {
                throw new InvalidOperationException("Telegram Core::Settings field is not present: " + name);
            }
            return item;
        }

        private void Add(string name, ItemKind kind, object value) {
            var item = new SettingItem(name, kind, value);
            _items.Add(item);
            _byName.Add(name, item);
        }

        private static List<StringStringPair> ReadStringStringMap(QtReader reader) {
            var count = reader.ReadInt32();
            if (count < 0 || count > 100000) {
                throw new InvalidDataException("Invalid Telegram string map count: " + count);
            }
            var result = new List<StringStringPair>();
            for (var i = 0; i != count; ++i) {
                result.Add(new StringStringPair { Key = reader.ReadString(), Value = reader.ReadString() });
            }
            return result;
        }

        private static List<long> ReadInt64List(QtReader reader) {
            var count = reader.ReadInt32();
            if (count < 0 || count > 100000) {
                throw new InvalidDataException("Invalid Telegram int64 list count: " + count);
            }
            var result = new List<long>();
            for (var i = 0; i != count; ++i) {
                result.Add(reader.ReadInt64());
            }
            return result;
        }

        private static List<ulong> ReadUInt64List(QtReader reader) {
            var count = reader.ReadInt32();
            if (count < 0 || count > 100000) {
                throw new InvalidDataException("Invalid Telegram uint64 list count: " + count);
            }
            var result = new List<ulong>();
            for (var i = 0; i != count; ++i) {
                result.Add(reader.ReadUInt64());
            }
            return result;
        }

        private static List<RecentEmojiItem> ReadRecentEmojiList(QtReader reader) {
            var count = reader.ReadInt32();
            if (count < 0 || count > 100000) {
                throw new InvalidDataException("Invalid Telegram recent emoji count: " + count);
            }
            var result = new List<RecentEmojiItem>();
            for (var i = 0; i != count; ++i) {
                result.Add(new RecentEmojiItem { Id = reader.ReadString(), Rating = reader.ReadUInt16() });
            }
            return result;
        }

        private static List<EmojiVariantItem> ReadEmojiVariantList(QtReader reader) {
            var count = reader.ReadInt32();
            if (count < 0 || count > 100000) {
                throw new InvalidDataException("Invalid Telegram emoji variant count: " + count);
            }
            var result = new List<EmojiVariantItem>();
            for (var i = 0; i != count; ++i) {
                result.Add(new EmojiVariantItem { Id = reader.ReadString(), Variant = reader.ReadUInt8() });
            }
            return result;
        }

        private static List<string> ReadStringList(QtReader reader) {
            var count = reader.ReadInt32();
            if (count < 0 || count > 100000) {
                throw new InvalidDataException("Invalid Telegram string list count: " + count);
            }
            var result = new List<string>();
            for (var i = 0; i != count; ++i) {
                result.Add(reader.ReadString());
            }
            return result;
        }

        private static List<ByteArrayPair> ReadByteArrayMap(QtReader reader) {
            var count = reader.ReadUInt32();
            if (count > 100000) {
                throw new InvalidDataException("Invalid Telegram byte array map count: " + count);
            }
            var result = new List<ByteArrayPair>();
            for (var i = 0U; i != count; ++i) {
                result.Add(new ByteArrayPair { Key = reader.ReadByteArray(), Value = reader.ReadByteArray() });
            }
            return result;
        }

        private static void WriteItem(QtWriter writer, SettingItem item) {
            switch (item.Kind) {
                case ItemKind.Int32:
                    writer.WriteInt32((int)item.Value);
                    break;
                case ItemKind.UInt32:
                    writer.WriteUInt32((uint)item.Value);
                    break;
                case ItemKind.Int64:
                    writer.WriteInt64((long)item.Value);
                    break;
                case ItemKind.UInt64:
                    writer.WriteUInt64((ulong)item.Value);
                    break;
                case ItemKind.UInt16:
                    writer.WriteUInt16((ushort)item.Value);
                    break;
                case ItemKind.UInt8:
                    writer.WriteUInt8((byte)item.Value);
                    break;
                case ItemKind.String:
                    writer.WriteString((string)item.Value);
                    break;
                case ItemKind.ByteArray:
                    writer.WriteByteArray((byte[])item.Value);
                    break;
                case ItemKind.StringStringMap:
                    WriteStringStringMap(writer, (List<StringStringPair>)item.Value);
                    break;
                case ItemKind.Int64List:
                    WriteInt64List(writer, (List<long>)item.Value);
                    break;
                case ItemKind.UInt64List:
                    WriteUInt64List(writer, (List<ulong>)item.Value);
                    break;
                case ItemKind.RecentEmojiList:
                    WriteRecentEmojiList(writer, (List<RecentEmojiItem>)item.Value);
                    break;
                case ItemKind.EmojiVariantList:
                    WriteEmojiVariantList(writer, (List<EmojiVariantItem>)item.Value);
                    break;
                case ItemKind.StringList:
                    WriteStringList(writer, (List<string>)item.Value);
                    break;
                case ItemKind.ByteArrayMap:
                    WriteByteArrayMap(writer, (List<ByteArrayPair>)item.Value);
                    break;
                default:
                    throw new InvalidOperationException("Unsupported Telegram item kind: " + item.Kind);
            }
        }

        private static void WriteStringStringMap(QtWriter writer, List<StringStringPair> value) {
            writer.WriteInt32(value.Count);
            foreach (var pair in value) {
                writer.WriteString(pair.Key);
                writer.WriteString(pair.Value);
            }
        }

        private static void WriteInt64List(QtWriter writer, List<long> value) {
            writer.WriteInt32(value.Count);
            foreach (var item in value) {
                writer.WriteInt64(item);
            }
        }

        private static void WriteUInt64List(QtWriter writer, List<ulong> value) {
            writer.WriteInt32(value.Count);
            foreach (var item in value) {
                writer.WriteUInt64(item);
            }
        }

        private static void WriteRecentEmojiList(QtWriter writer, List<RecentEmojiItem> value) {
            writer.WriteInt32(value.Count);
            foreach (var item in value) {
                writer.WriteString(item.Id);
                writer.WriteUInt16(item.Rating);
            }
        }

        private static void WriteEmojiVariantList(QtWriter writer, List<EmojiVariantItem> value) {
            writer.WriteInt32(value.Count);
            foreach (var item in value) {
                writer.WriteString(item.Id);
                writer.WriteUInt8(item.Variant);
            }
        }

        private static void WriteStringList(QtWriter writer, List<string> value) {
            writer.WriteInt32(value.Count);
            foreach (var item in value) {
                writer.WriteString(item);
            }
        }

        private static void WriteByteArrayMap(QtWriter writer, List<ByteArrayPair> value) {
            writer.WriteUInt32((uint)value.Count);
            foreach (var pair in value) {
                writer.WriteByteArray(pair.Key);
                writer.WriteByteArray(pair.Value);
            }
        }

        private static object ConvertRawToPublic(FieldSpec spec, object rawValue) {
            switch (spec.Kind) {
                case PublicKind.BoolInt32:
                    return ((int)rawValue) == 1;
                case PublicKind.Int32:
                case PublicKind.UInt32:
                case PublicKind.UInt16:
                case PublicKind.String:
                    return rawValue;
                case PublicKind.EnumInt32:
                    return FormatEnumValue(spec, (int)rawValue);
                case PublicKind.SendFilesWay:
                    return FormatSendFilesWay((int)rawValue);
                default:
                    throw new InvalidOperationException("Unsupported Telegram public kind: " + spec.Kind);
            }
        }

        private static object ConvertPublicToRaw(FieldSpec spec, object value) {
            switch (spec.Kind) {
                case PublicKind.BoolInt32:
                    return ConvertToBool(value) ? 1 : 0;
                case PublicKind.Int32:
                    return Convert.ToInt32(value);
                case PublicKind.UInt32:
                    return Convert.ToUInt32(value);
                case PublicKind.UInt16:
                    return Convert.ToUInt16(value);
                case PublicKind.String:
                    return Convert.ToString(value);
                case PublicKind.EnumInt32:
                    return ParseEnumValue(spec, value);
                case PublicKind.SendFilesWay:
                    return ParseSendFilesWay(value);
                default:
                    throw new InvalidOperationException("Unsupported Telegram public kind: " + spec.Kind);
            }
        }

        private static bool ConvertToBool(object value) {
            if (value is bool) {
                return (bool)value;
            }
            if (value is string) {
                return bool.Parse((string)value);
            }
            return Convert.ToInt32(value) != 0;
        }

        private static string FormatEnumValue(FieldSpec spec, int value) {
            string name;
            return spec.EnumNames.TryGetValue(value, out name) ? name : value.ToString();
        }

        private static int ParseEnumValue(FieldSpec spec, object value) {
            if (!(value is string)) {
                return Convert.ToInt32(value);
            }
            var text = (string)value;
            foreach (var pair in spec.EnumNames) {
                if (StringComparer.Ordinal.Equals(pair.Value, text)) {
                    return pair.Key;
                }
            }
            throw new InvalidOperationException("Unsupported value for " + spec.Name + ": " + text);
        }

        private static string FormatSendFilesWay(int value) {
            var large = (value & 4) != 0;
            var baseValue = value & ~4;
            string name;
            switch (baseValue) {
                case 0: name = "AlbumPhotos"; break;
                case 1: name = "Photos"; break;
                case 2: name = "Files"; break;
                case 3: name = "AlbumFiles"; break;
                default: return value.ToString();
            }
            return large ? name + "Large" : name;
        }

        private static int ParseSendFilesWay(object value) {
            if (!(value is string)) {
                return Convert.ToInt32(value);
            }
            var text = (string)value;
            var large = false;
            if (text.EndsWith("Large", StringComparison.Ordinal)) {
                large = true;
                text = text.Substring(0, text.Length - "Large".Length);
            }
            int baseValue;
            if (text == "AlbumPhotos") {
                baseValue = 0;
            } else if (text == "Photos") {
                baseValue = 1;
            } else if (text == "Files") {
                baseValue = 2;
            } else if (text == "AlbumFiles") {
                baseValue = 3;
            } else {
                throw new InvalidOperationException("Unsupported SendFilesWay value: " + value);
            }
            return large ? (baseValue | 4) : baseValue;
        }

        private static bool ObjectEquals(object left, object right) {
            if (left is byte[] && right is byte[]) {
                return ByteArrayEquals((byte[])left, (byte[])right);
            }
            return object.Equals(left, right);
        }

        private static bool ByteArrayEquals(byte[] left, byte[] right) {
            if (object.ReferenceEquals(left, right)) {
                return true;
            }
            if (left == null || right == null || left.Length != right.Length) {
                return false;
            }
            for (var i = 0; i != left.Length; ++i) {
                if (left[i] != right[i]) {
                    return false;
                }
            }
            return true;
        }
    }

    public sealed class SettingsFile {
        private const uint ApplicationSettingsBlock = 0x5e;
        private static readonly byte[] Magic = Encoding.ASCII.GetBytes("TDF$");
        private readonly List<SettingsBlock> _blocks = new List<SettingsBlock>();
        private int _version;
        private byte[] _salt;

        private static readonly Dictionary<string, FieldSpec> FieldSpecs = CreateFieldSpecs();

        public static SettingsFile Load(string path) {
            var bytes = File.ReadAllBytes(path);
            if (bytes.Length < 24) {
                throw new InvalidDataException("Telegram settingss is too short.");
            }
            for (var i = 0; i != Magic.Length; ++i) {
                if (bytes[i] != Magic[i]) {
                    throw new InvalidDataException("Telegram settingss magic is invalid.");
                }
            }

            var version = ReadInt32LittleEndian(bytes, 4);
            var dataSize = bytes.Length - 8 - 16;
            var data = Slice(bytes, 8, dataSize);
            var expectedMd5 = ComputeTdfMd5(data, dataSize, version);
            for (var i = 0; i != 16; ++i) {
                if (bytes[8 + dataSize + i] != expectedMd5[i]) {
                    throw new InvalidDataException("Telegram settingss MD5 signature is invalid.");
                }
            }

            var dataReader = new QtReader(data);
            var salt = dataReader.ReadByteArray();
            var encrypted = dataReader.ReadByteArray();
            if (!dataReader.End) {
                throw new InvalidDataException("Telegram settingss contains unexpected top-level data.");
            }
            if (salt == null || salt.Length != 32) {
                throw new InvalidDataException("Telegram settingss salt size is invalid.");
            }

            var key = CreateLegacyLocalKey(salt);
            var payload = DecryptLocal(encrypted, key);

            var result = new SettingsFile();
            result._version = version;
            result._salt = salt;
            result.ReadBlocks(payload);
            return result;
        }

        public void Save(string path) {
            var settingsPayload = WriteBlocks();
            var key = CreateLegacyLocalKey(_salt);
            var encrypted = EncryptLocal(settingsPayload, key);

            var dataWriter = new QtWriter();
            dataWriter.WriteByteArray(_salt);
            dataWriter.WriteByteArray(encrypted);
            var data = dataWriter.ToArray();
            var md5 = ComputeTdfMd5(data, data.Length, _version);

            var output = new MemoryStream();
            output.Write(Magic, 0, Magic.Length);
            WriteInt32LittleEndian(output, _version);
            output.Write(data, 0, data.Length);
            output.Write(md5, 0, md5.Length);

            var temp = path + ".InitWin.tmp";
            File.WriteAllBytes(temp, output.ToArray());
            if (File.Exists(path)) {
                File.Replace(temp, path, null);
            } else {
                File.Move(temp, path);
            }
        }

        public bool IsDesired(IDictionary overrides) {
            var coreSettings = GetApplicationSettings();
            foreach (DictionaryEntry entry in GetDictionary(overrides, "CoreSettings")) {
                var name = Convert.ToString(entry.Key);
                var expected = coreSettings.NormalizeFieldOverride(name, entry.Value);
                if (!coreSettings.FieldEquals(name, expected)) {
                    return false;
                }
            }
            foreach (DictionaryEntry entry in GetDictionary(overrides, "Preferences")) {
                var key = PreferenceKeyToBytes(Convert.ToString(entry.Key));
                var expected = NormalizePreferenceOverride(entry.Value);
                var current = coreSettings.GetPreference(key);
                if (!ByteArrayEquals(current, expected)) {
                    return false;
                }
            }
            return true;
        }

        public string FormatCurrentForOverrides(IDictionary overrides) {
            return FormatOverrides(overrides, false);
        }

        public string FormatExpectedForOverrides(IDictionary overrides) {
            return FormatOverrides(overrides, true);
        }

        public string[] ApplyOverrides(IDictionary overrides) {
            var changes = new List<string>();
            var coreSettings = GetApplicationSettings();

            foreach (DictionaryEntry entry in SortedEntries(GetDictionary(overrides, "CoreSettings"))) {
                var name = Convert.ToString(entry.Key);
                var currentPublic = coreSettings.GetPublicValue(name);
                var expectedRaw = coreSettings.NormalizeFieldOverride(name, entry.Value);
                if (coreSettings.FieldEquals(name, expectedRaw)) {
                    continue;
                }
                coreSettings.SetFieldRaw(name, expectedRaw);
                var expectedPublic = coreSettings.GetPublicValue(name);
                changes.Add("CoreSettings." + name + ": " + FormatValue(currentPublic) + " -> " + FormatValue(expectedPublic));
            }

            foreach (DictionaryEntry entry in SortedEntries(GetDictionary(overrides, "Preferences"))) {
                var name = Convert.ToString(entry.Key);
                var key = PreferenceKeyToBytes(name);
                var expected = NormalizePreferenceOverride(entry.Value);
                var current = coreSettings.GetPreference(key);
                if (ByteArrayEquals(current, expected)) {
                    continue;
                }
                coreSettings.SetPreference(key, expected);
                changes.Add("Preferences." + name + ": " + FormatPreference(current, entry.Value) + " -> " + FormatPreference(expected, entry.Value));
            }

            return changes.ToArray();
        }

        internal static FieldSpec GetFieldSpec(string name) {
            FieldSpec spec;
            if (!FieldSpecs.TryGetValue(name, out spec)) {
                throw new InvalidOperationException("Unsupported Telegram Core::Settings override field: " + name);
            }
            return spec;
        }

        private void ReadBlocks(byte[] payload) {
            var reader = new QtReader(payload);
            while (!reader.End) {
                var id = reader.ReadUInt32();
                var payloadStart = reader.Position;
                CoreSettings applicationSettings = null;

                switch (id) {
                    case 0x06:
                    case 0x07:
                    case 0x0a:
                    case 0x0c:
                    case 0x0d:
                    case 0x1d:
                    case 0x57:
                    case 0x58:
                        reader.ReadInt32();
                        break;
                    case 0x23:
                        reader.ReadString();
                        break;
                    case 0x4e:
                    case 0x5a:
                        reader.ReadUInt64();
                        break;
                    case 0x54:
                        reader.ReadUInt64();
                        reader.ReadUInt64();
                        reader.ReadUInt32();
                        break;
                    case 0x55:
                        reader.ReadInt32();
                        reader.ReadInt32();
                        break;
                    case 0x5e:
                        applicationSettings = CoreSettings.Parse(reader.ReadByteArray());
                        break;
                    case 0x60:
                        reader.ReadByteArray();
                        break;
                    case 0x61:
                        reader.ReadUInt64();
                        reader.ReadUInt64();
                        break;
                    default:
                        throw new InvalidDataException("Unsupported Telegram settings block id: 0x" + id.ToString("x"));
                }

                _blocks.Add(new SettingsBlock {
                    Id = id,
                    RawPayload = reader.Slice(payloadStart, reader.Position - payloadStart),
                    ApplicationSettings = applicationSettings
                });
            }

            GetApplicationSettings();
        }

        private byte[] WriteBlocks() {
            var writer = new QtWriter();
            foreach (var block in _blocks) {
                writer.WriteUInt32(block.Id);
                if (block.Id == ApplicationSettingsBlock) {
                    writer.WriteByteArray(block.ApplicationSettings.Serialize());
                } else {
                    writer.WriteRaw(block.RawPayload);
                }
            }
            return writer.ToArray();
        }

        private CoreSettings GetApplicationSettings() {
            foreach (var block in _blocks) {
                if (block.Id == ApplicationSettingsBlock && block.ApplicationSettings != null) {
                    return block.ApplicationSettings;
                }
            }
            throw new InvalidDataException("Telegram settingss does not contain dbiApplicationSettings.");
        }

        private string FormatOverrides(IDictionary overrides, bool expected) {
            var lines = new List<string>();
            var coreSettings = GetApplicationSettings();
            foreach (DictionaryEntry entry in SortedEntries(GetDictionary(overrides, "CoreSettings"))) {
                var name = Convert.ToString(entry.Key);
                object value;
                if (expected) {
                    var raw = coreSettings.NormalizeFieldOverride(name, entry.Value);
                    var original = coreSettings.GetItem(name);
                    var oldRaw = original.Value;
                    original.Value = raw;
                    try {
                        value = coreSettings.GetPublicValue(name);
                    } finally {
                        original.Value = oldRaw;
                    }
                } else {
                    value = coreSettings.GetPublicValue(name);
                }
                lines.Add("CoreSettings." + name + " = " + FormatValue(value));
            }
            foreach (DictionaryEntry entry in SortedEntries(GetDictionary(overrides, "Preferences"))) {
                var name = Convert.ToString(entry.Key);
                var bytes = expected
                    ? NormalizePreferenceOverride(entry.Value)
                    : coreSettings.GetPreference(PreferenceKeyToBytes(name));
                lines.Add("Preferences." + name + " = " + FormatPreference(bytes, entry.Value));
            }
            return string.Join(Environment.NewLine, lines.ToArray());
        }

        private static IDictionary GetDictionary(IDictionary source, string key) {
            if (source == null || !source.Contains(key) || source[key] == null) {
                return new Hashtable();
            }
            var result = source[key] as IDictionary;
            if (result == null) {
                throw new InvalidOperationException("Telegram override section must be a hashtable: " + key);
            }
            return result;
        }

        private static List<DictionaryEntry> SortedEntries(IDictionary dictionary) {
            var entries = new List<DictionaryEntry>();
            foreach (DictionaryEntry entry in dictionary) {
                entries.Add(entry);
            }
            entries.Sort(delegate(DictionaryEntry left, DictionaryEntry right) {
                return StringComparer.Ordinal.Compare(Convert.ToString(left.Key), Convert.ToString(right.Key));
            });
            return entries;
        }

        private static string FormatValue(object value) {
            if (value == null) {
                return "<null>";
            }
            if (value is bool) {
                return (bool)value ? "true" : "false";
            }
            if (value is string) {
                return '"' + Escape((string)value) + '"';
            }
            return Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture);
        }

        private static string FormatPreference(byte[] bytes, object overrideValue) {
            if (IsBooleanPreferenceOverride(overrideValue)) {
                return (bytes != null && bytes.Length != 0) ? "true" : "false";
            }
            if (bytes == null) {
                return "<missing>";
            }
            return '"' + Escape(Encoding.UTF8.GetString(bytes)) + '"';
        }

        private static string Escape(string value) {
            return value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n").Replace("\t", "\\t");
        }

        private static byte[] PreferenceKeyToBytes(string key) {
            return Encoding.UTF8.GetBytes(key);
        }

        private static byte[] NormalizePreferenceOverride(object value) {
            if (value is bool) {
                return (bool)value ? new byte[] { 1 } : new byte[0];
            }
            var dictionary = value as IDictionary;
            if (dictionary != null) {
                var type = dictionary.Contains("Type") ? Convert.ToString(dictionary["Type"]) : "Utf8String";
                var typedValue = dictionary.Contains("Value") ? dictionary["Value"] : null;
                if (type == "Boolean") {
                    var enabled = typedValue is bool ? (bool)typedValue : Convert.ToBoolean(typedValue);
                    return enabled ? new byte[] { 1 } : new byte[0];
                }
                if (type == "Utf8String") {
                    return Encoding.UTF8.GetBytes(Convert.ToString(typedValue));
                }
                throw new InvalidOperationException("Unsupported Telegram preference override type: " + type);
            }
            return Encoding.UTF8.GetBytes(Convert.ToString(value));
        }

        private static bool IsBooleanPreferenceOverride(object value) {
            if (value is bool) {
                return true;
            }
            var dictionary = value as IDictionary;
            return dictionary != null
                && dictionary.Contains("Type")
                && Convert.ToString(dictionary["Type"]) == "Boolean";
        }

        private static Dictionary<string, FieldSpec> CreateFieldSpecs() {
            var result = new Dictionary<string, FieldSpec>(StringComparer.Ordinal);
            Add(result, "AdaptiveForWide", PublicKind.BoolInt32);
            Add(result, "AskDownloadPath", PublicKind.BoolInt32);
            Add(result, "AutoDownloadDictionaries", PublicKind.BoolInt32);
            Add(result, "ChatFiltersHorizontal", PublicKind.BoolInt32);
            Add(result, "CornerReaction", PublicKind.BoolInt32);
            Add(result, "CornerReply", PublicKind.BoolInt32);
            Add(result, "CountUnreadMessages", PublicKind.BoolInt32);
            Add(result, "DesktopNotify", PublicKind.BoolInt32);
            Add(result, "DisableOpenGL", PublicKind.BoolInt32);
            Add(result, "FlashBounceNotify", PublicKind.BoolInt32);
            Add(result, "GroupCallNoiseSuppression", PublicKind.BoolInt32);
            Add(result, "HardwareAcceleratedVideo", PublicKind.BoolInt32);
            Add(result, "IgnoreBatterySaving", PublicKind.BoolInt32);
            Add(result, "IncludeMutedCounter", PublicKind.BoolInt32);
            Add(result, "IncludeMutedCounterFolders", PublicKind.BoolInt32);
            Add(result, "IpRevealWarning", PublicKind.BoolInt32);
            Add(result, "LargeEmoji", PublicKind.BoolInt32);
            Add(result, "LoopAnimatedStickers", PublicKind.BoolInt32);
            Add(result, "MainMenuAccountsShown", PublicKind.BoolInt32);
            Add(result, "NativeWindowFrame", PublicKind.BoolInt32);
            Add(result, "NotifyAboutPinned", PublicKind.BoolInt32);
            Add(result, "NotifyFromAll", PublicKind.BoolInt32);
            Add(result, "RecordVideoMessages", PublicKind.BoolInt32);
            Add(result, "ReplaceEmoji", PublicKind.BoolInt32);
            Add(result, "SkipToastsInFocus", PublicKind.BoolInt32);
            Add(result, "SoundNotify", PublicKind.BoolInt32);
            Add(result, "SpellcheckerEnabled", PublicKind.BoolInt32);
            Add(result, "StoriesClickTooltipHidden", PublicKind.BoolInt32);
            Add(result, "SuggestAnimatedEmoji", PublicKind.BoolInt32);
            Add(result, "SuggestEmoji", PublicKind.BoolInt32);
            Add(result, "SuggestStickersByEmoji", PublicKind.BoolInt32);
            Add(result, "SystemAccentColorEnabled", PublicKind.BoolInt32);
            Add(result, "SystemDarkModeEnabled", PublicKind.BoolInt32);
            Add(result, "SystemTextReplace", PublicKind.BoolInt32);
            Add(result, "SystemUnlockEnabled", PublicKind.BoolInt32);
            Add(result, "TabbedSelectorSectionEnabled", PublicKind.BoolInt32);
            Add(result, "ThirdSectionInfoEnabled", PublicKind.BoolInt32);
            Add(result, "TranslateButtonEnabled", PublicKind.BoolInt32);
            Add(result, "TranslateChatEnabled", PublicKind.BoolInt32);
            Add(result, "TrayIconMonochrome", PublicKind.BoolInt32);
            Add(result, "TtlVoiceClickTooltipHidden", PublicKind.BoolInt32);
            Add(result, "UsePlatformTranslation", PublicKind.BoolInt32);
            Add(result, "WindowTitleHideAccountName", PublicKind.BoolInt32);
            Add(result, "WindowTitleHideChatName", PublicKind.BoolInt32);
            Add(result, "WindowTitleHideTotalUnread", PublicKind.BoolInt32);
            Add(result, "AutoLock", PublicKind.Int32);
            Add(result, "CallInputVolume", PublicKind.Int32);
            Add(result, "CallOutputVolume", PublicKind.Int32);
            Add(result, "IvZoom", PublicKind.Int32);
            Add(result, "NotificationsCount", PublicKind.Int32);
            Add(result, "NotificationsDisplayChecksum", PublicKind.Int32);
            Add(result, "NotificationsVolume", PublicKind.UInt16);
            Add(result, "QuickDialogAction", PublicKind.EnumInt32, EnumMap("Mute", "Pin", "Read", "Archive", "Delete", "Disabled"));
            Add(result, "ChatQuickAction", PublicKind.EnumInt32, EnumMap("Reply", "React", "None"));
            Add(result, "CloseBehavior", PublicKind.EnumInt32, EnumMap("Quit", "CloseToTaskbar", "RunInBackground"));
            Add(result, "NativeNotifications", PublicKind.EnumInt32, EnumMap("System", "Enabled", "Disabled"));
            Add(result, "NotificationsCorner", PublicKind.EnumInt32, EnumMap("TopLeft", "TopRight", "BottomRight", "BottomLeft"));
            Add(result, "NotifyView", PublicKind.EnumInt32, EnumMap("ShowPreview", "ShowName", "ShowNothing"));
            Add(result, "PlayerOrderMode", PublicKind.EnumInt32, EnumMap("Default", "Reverse", "Shuffle"));
            Add(result, "PlayerRepeatMode", PublicKind.EnumInt32, EnumMap("None", "One", "All"));
            Add(result, "SendSubmitWay", PublicKind.EnumInt32, EnumMap("Enter", "CtrlEnter"));
            Add(result, "WorkMode", PublicKind.EnumInt32, EnumMap("WindowAndTray", "TrayOnly", "WindowOnly"));
            Add(result, "SendFilesWay", PublicKind.SendFilesWay);
            Add(result, "CustomFontFamily", PublicKind.String);
            return result;
        }

        private static void Add(Dictionary<string, FieldSpec> specs, string name, PublicKind kind) {
            specs.Add(name, new FieldSpec(name, kind));
        }

        private static void Add(Dictionary<string, FieldSpec> specs, string name, PublicKind kind, Dictionary<int, string> enumNames) {
            specs.Add(name, new FieldSpec(name, kind, enumNames));
        }

        private static Dictionary<int, string> EnumMap(params string[] names) {
            var result = new Dictionary<int, string>();
            for (var i = 0; i != names.Length; ++i) {
                result.Add(i, names[i]);
            }
            return result;
        }

        private static byte[] CreateLegacyLocalKey(byte[] salt) {
            return Pbkdf2Sha1(new byte[0], salt, 4, 256);
        }

        private static byte[] Pbkdf2Sha1(byte[] password, byte[] salt, int iterations, int length) {
            var result = new byte[length];
            var offset = 0;
            var blockIndex = 1;
            using (var hmac = new HMACSHA1(password)) {
                while (offset < length) {
                    var blockSalt = new byte[salt.Length + 4];
                    Buffer.BlockCopy(salt, 0, blockSalt, 0, salt.Length);
                    blockSalt[salt.Length] = (byte)(blockIndex >> 24);
                    blockSalt[salt.Length + 1] = (byte)(blockIndex >> 16);
                    blockSalt[salt.Length + 2] = (byte)(blockIndex >> 8);
                    blockSalt[salt.Length + 3] = (byte)blockIndex;

                    var u = hmac.ComputeHash(blockSalt);
                    var t = (byte[])u.Clone();
                    for (var i = 1; i != iterations; ++i) {
                        u = hmac.ComputeHash(u);
                        for (var j = 0; j != t.Length; ++j) {
                            t[j] ^= u[j];
                        }
                    }

                    var toCopy = Math.Min(t.Length, length - offset);
                    Buffer.BlockCopy(t, 0, result, offset, toCopy);
                    offset += toCopy;
                    ++blockIndex;
                }
            }
            return result;
        }

        private static byte[] DecryptLocal(byte[] encrypted, byte[] authKey) {
            if (encrypted == null || encrypted.Length <= 16 || (encrypted.Length & 15) != 0) {
                throw new InvalidDataException("Telegram encrypted settings payload size is invalid.");
            }
            var msgKey = Slice(encrypted, 0, 16);
            var ciphertext = Slice(encrypted, 16, encrypted.Length - 16);
            var aes = PrepareAesOldMtp(authKey, msgKey, false);
            var decrypted = AesIgeDecrypt(ciphertext, aes.Key, aes.Iv);

            var sha1 = SHA1.Create().ComputeHash(decrypted);
            for (var i = 0; i != 16; ++i) {
                if (sha1[i] != msgKey[i]) {
                    throw new InvalidDataException("Telegram encrypted settings SHA1 check failed.");
                }
            }

            var dataLength = ReadUInt32LittleEndian(decrypted, 0);
            if (dataLength < 4 || dataLength > decrypted.Length || dataLength <= decrypted.Length - 16) {
                throw new InvalidDataException("Telegram decrypted settings payload length is invalid.");
            }
            return Slice(decrypted, 4, (int)dataLength - 4);
        }

        private static byte[] EncryptLocal(byte[] payload, byte[] authKey) {
            var dataLength = 4 + payload.Length;
            var fullLength = ((dataLength + 15) / 16) * 16;
            var plain = new byte[fullLength];
            WriteUInt32LittleEndian(plain, 0, (uint)dataLength);
            Buffer.BlockCopy(payload, 0, plain, 4, payload.Length);
            if (fullLength > dataLength) {
                using (var rng = RandomNumberGenerator.Create()) {
                    var padding = new byte[fullLength - dataLength];
                    rng.GetBytes(padding);
                    Buffer.BlockCopy(padding, 0, plain, dataLength, padding.Length);
                }
            }

            var sha1 = SHA1.Create().ComputeHash(plain);
            var msgKey = Slice(sha1, 0, 16);
            var aes = PrepareAesOldMtp(authKey, msgKey, false);
            var ciphertext = AesIgeEncrypt(plain, aes.Key, aes.Iv);
            var result = new byte[msgKey.Length + ciphertext.Length];
            Buffer.BlockCopy(msgKey, 0, result, 0, msgKey.Length);
            Buffer.BlockCopy(ciphertext, 0, result, msgKey.Length, ciphertext.Length);
            return result;
        }

        private sealed class AesParameters {
            public byte[] Key;
            public byte[] Iv;
        }

        private static AesParameters PrepareAesOldMtp(byte[] authKey, byte[] msgKey, bool send) {
            var x = send ? 0 : 8;
            var sha1a = Sha1(Concat(msgKey, Slice(authKey, x, 32)));
            var sha1b = Sha1(Concat(Slice(authKey, 32 + x, 16), msgKey, Slice(authKey, 48 + x, 16)));
            var sha1c = Sha1(Concat(Slice(authKey, 64 + x, 32), msgKey));
            var sha1d = Sha1(Concat(msgKey, Slice(authKey, 96 + x, 32)));

            var key = new byte[32];
            Buffer.BlockCopy(sha1a, 0, key, 0, 8);
            Buffer.BlockCopy(sha1b, 8, key, 8, 12);
            Buffer.BlockCopy(sha1c, 4, key, 20, 12);

            var iv = new byte[32];
            Buffer.BlockCopy(sha1a, 8, iv, 0, 12);
            Buffer.BlockCopy(sha1b, 0, iv, 12, 8);
            Buffer.BlockCopy(sha1c, 16, iv, 20, 4);
            Buffer.BlockCopy(sha1d, 0, iv, 24, 8);

            return new AesParameters { Key = key, Iv = iv };
        }

        private static byte[] AesIgeEncrypt(byte[] input, byte[] key, byte[] iv) {
            return AesIge(input, key, iv, true);
        }

        private static byte[] AesIgeDecrypt(byte[] input, byte[] key, byte[] iv) {
            return AesIge(input, key, iv, false);
        }

        private static byte[] AesIge(byte[] input, byte[] key, byte[] iv, bool encrypt) {
            if ((input.Length & 15) != 0 || iv.Length != 32) {
                throw new InvalidDataException("AES-IGE input length is invalid.");
            }
            var result = new byte[input.Length];
            var previousCipher = Slice(iv, 0, 16);
            var previousPlain = Slice(iv, 16, 16);

            using (var aes = Aes.Create()) {
                aes.Mode = CipherMode.ECB;
                aes.Padding = PaddingMode.None;
                aes.Key = key;
                using (var transform = encrypt ? aes.CreateEncryptor() : aes.CreateDecryptor()) {
                    var x = new byte[16];
                    var y = new byte[16];
                    var transformed = new byte[16];

                    for (var offset = 0; offset < input.Length; offset += 16) {
                        if (encrypt) {
                            XorBlock(input, offset, previousCipher, 0, x, 0);
                            TransformBlock(transform, x, transformed);
                            XorBlock(transformed, 0, previousPlain, 0, y, 0);
                            Buffer.BlockCopy(y, 0, result, offset, 16);
                            Buffer.BlockCopy(input, offset, previousPlain, 0, 16);
                            Buffer.BlockCopy(y, 0, previousCipher, 0, 16);
                        } else {
                            XorBlock(input, offset, previousPlain, 0, x, 0);
                            TransformBlock(transform, x, transformed);
                            XorBlock(transformed, 0, previousCipher, 0, y, 0);
                            Buffer.BlockCopy(y, 0, result, offset, 16);
                            Buffer.BlockCopy(input, offset, previousCipher, 0, 16);
                            Buffer.BlockCopy(y, 0, previousPlain, 0, 16);
                        }
                    }
                }
            }

            return result;
        }

        private static void TransformBlock(ICryptoTransform transform, byte[] input, byte[] output) {
            var written = transform.TransformBlock(input, 0, 16, output, 0);
            if (written != 16) {
                throw new CryptographicException("AES block transform failed.");
            }
        }

        private static void XorBlock(byte[] left, int leftOffset, byte[] right, int rightOffset, byte[] output, int outputOffset) {
            for (var i = 0; i != 16; ++i) {
                output[outputOffset + i] = (byte)(left[leftOffset + i] ^ right[rightOffset + i]);
            }
        }

        private static byte[] ComputeTdfMd5(byte[] data, int dataSize, int version) {
            using (var stream = new MemoryStream()) {
                stream.Write(data, 0, data.Length);
                WriteInt32LittleEndian(stream, dataSize);
                WriteInt32LittleEndian(stream, version);
                stream.Write(Magic, 0, Magic.Length);
                return MD5.Create().ComputeHash(stream.ToArray());
            }
        }

        private static byte[] Sha1(byte[] bytes) {
            return SHA1.Create().ComputeHash(bytes);
        }

        private static byte[] Concat(params byte[][] arrays) {
            var length = 0;
            foreach (var array in arrays) {
                length += array.Length;
            }
            var result = new byte[length];
            var offset = 0;
            foreach (var array in arrays) {
                Buffer.BlockCopy(array, 0, result, offset, array.Length);
                offset += array.Length;
            }
            return result;
        }

        private static byte[] Slice(byte[] source, int start, int length) {
            var result = new byte[length];
            Buffer.BlockCopy(source, start, result, 0, length);
            return result;
        }

        private static bool ByteArrayEquals(byte[] left, byte[] right) {
            if (object.ReferenceEquals(left, right)) {
                return true;
            }
            if (left == null || right == null || left.Length != right.Length) {
                return false;
            }
            for (var i = 0; i != left.Length; ++i) {
                if (left[i] != right[i]) {
                    return false;
                }
            }
            return true;
        }

        private static int ReadInt32LittleEndian(byte[] source, int offset) {
            return unchecked((int)ReadUInt32LittleEndian(source, offset));
        }

        private static uint ReadUInt32LittleEndian(byte[] source, int offset) {
            return (uint)(source[offset]
                | (source[offset + 1] << 8)
                | (source[offset + 2] << 16)
                | (source[offset + 3] << 24));
        }

        private static void WriteInt32LittleEndian(Stream stream, int value) {
            WriteUInt32LittleEndian(stream, unchecked((uint)value));
        }

        private static void WriteUInt32LittleEndian(Stream stream, uint value) {
            stream.WriteByte((byte)value);
            stream.WriteByte((byte)(value >> 8));
            stream.WriteByte((byte)(value >> 16));
            stream.WriteByte((byte)(value >> 24));
        }

        private static void WriteUInt32LittleEndian(byte[] target, int offset, uint value) {
            target[offset] = (byte)value;
            target[offset + 1] = (byte)(value >> 8);
            target[offset + 2] = (byte)(value >> 16);
            target[offset + 3] = (byte)(value >> 24);
        }
    }
}
'@
}

function InitWin-ImportTelegramSettingsOverrides {
    param([Parameter(Mandatory)][string] $Path)

    $overrides = InitWin-ImportPowerShellDataFile -Path $Path
    $knownKeys = @('CoreSettings', 'Preferences')
    foreach ($key in $overrides.Keys) {
        if ($key -notin $knownKeys) {
            throw "Unknown Telegram settings override key in $Path`: $key"
        }
    }

    $result = @{
        CoreSettings = @{}
        Preferences = @{}
    }
    if ($overrides.ContainsKey('CoreSettings')) {
        $result.CoreSettings = $overrides.CoreSettings
    }
    if ($overrides.ContainsKey('Preferences')) {
        $result.Preferences = $overrides.Preferences
    }
    $result
}

function InitWin-TestTelegramSettingsOverrides {
    param(
        [Parameter(Mandatory)][string] $SettingsPath,
        [Parameter(Mandatory)][string] $OverridesPath
    )

    $overrides = InitWin-ImportTelegramSettingsOverrides -Path $OverridesPath
    if (($overrides.CoreSettings.Count -eq 0) -and ($overrides.Preferences.Count -eq 0)) {
        return InitWin-NewValidationResult -Status Desired
    }
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        return InitWin-NewValidationResult `
            -Status Unset `
            -Target "Telegram settingss: $SettingsPath" `
            -Current '<missing>' `
            -Expected 'created by Telegram' `
            -Reason 'settingss 不存在；Apply 时会等待用户启动 Telegram 生成它。'
    }

    $settings = [InitWin.Telegram.SettingsFile]::Load($SettingsPath)
    if ($settings.IsDesired($overrides)) {
        return InitWin-NewValidationResult -Status Desired
    }

    InitWin-NewValidationResult `
        -Status Conflict `
        -Target 'Telegram settingss overrides' `
        -Current ($settings.FormatCurrentForOverrides($overrides)) `
        -Expected ($settings.FormatExpectedForOverrides($overrides))
}

function InitWin-SetTelegramSettingsOverrides {
    param(
        [Parameter(Mandatory)][string] $SettingsPath,
        [Parameter(Mandatory)][string] $OverridesPath
    )

    $overrides = InitWin-ImportTelegramSettingsOverrides -Path $OverridesPath
    if (($overrides.CoreSettings.Count -eq 0) -and ($overrides.Preferences.Count -eq 0)) {
        return
    }
    while (-not (Test-Path -LiteralPath $SettingsPath)) {
        $answer = Read-Host 'Telegram settingss 不存在。请启动 Telegram，完成初始化后回到这里按 Enter 重试；输入 N 跳过'
        if ($answer -cin @('N', 'n')) {
            InitWin-WriteDetail 'settingss overrides skipped' -ForegroundColor Yellow
            return
        }

        Get-Process -Name 'Telegram' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

    $settings = [InitWin.Telegram.SettingsFile]::Load($SettingsPath)
    $changes = $settings.ApplyOverrides($overrides)
    if ($changes.Count -eq 0) {
        InitWin-WriteDetail 'settingss overrides already desired'
        return
    }

    $settings.Save($SettingsPath)
    foreach ($change in $changes) {
        InitWin-WriteDetail "settingss: $change"
    }
}
