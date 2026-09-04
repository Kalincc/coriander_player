use std::{
    collections::HashSet,
    fs::{self},
    io::{self, Cursor, Write},
    path::{Path, PathBuf},
    time::{Duration, UNIX_EPOCH},
};

use image::imageops;
use lofty::prelude::{Accessor, AudioFile, ItemKey, TaggedFileExt};
use windows::{
    core::Interface,
    core::HSTRING,
    Storage::{
        FileProperties::ThumbnailMode,
        StorageFile,
        Streams::{DataReader, IInputStream},
    },
};

use crate::frb_generated::StreamSink;

use super::logger::log_to_dart;

/// K: extension, V: can read tags by using Lofty
static SUPPORT_FORMAT: phf::Map<&'static str, bool> = phf::phf_map! {
    "mp3" => true, "mp2" => false, "mp1" => false,
    "ogg" => true,
    "wav" => true, "wave" => true,
    "aif" => true, "aiff" => true, "aifc" => true,
    // 通过 Windows 系统支持
    "asf" => false, "wma" => false,
    "aac" => true, "adts" => true,
    "m4a" => true,
    "ac3" => false,
    "amr" => false, "3ga" => false,
    "flac" => true,
    "mpc" => true,
    // 插件支持
    "mid" => false,
    "wv" => true, "wvc" => true,
    "opus" => true,
    "dsf" => false, "dff" => false,
    "ape" => true,
};

pub struct IndexActionState {
    /// completed / total
    pub progress: f64,

    /// describe action state
    pub message: String,
}

#[derive(Debug)]
struct Audio {
    title: String,
    artist: String,
    album: String,
    track: Option<u32>,
    /// in secs
    duration: u64,
    /// kbps
    bitrate: Option<u32>,
    sample_rate: Option<u32>,
    /// absolute path
    path: String,
    /// secs since UNIX_EPOCH
    modified: u64,
    /// secs since UNIX_EPOCH
    created: u64,
    /// 标签获取方式
    by: Option<String>,
}

impl Audio {
    fn new_with_path(path: impl AsRef<Path>, by: Option<String>) -> Option<Self> {
        let path = path.as_ref();
        Some(Audio {
            title: path.file_name()?.to_string_lossy().to_string(),
            artist: "UNKNOWN".to_string(),
            album: "UNKNOWN".to_string(),
            track: None,
            duration: 0,
            bitrate: None,
            sample_rate: None,
            path: path.to_string_lossy().to_string(),
            modified: 0,
            created: 0,
            by,
        })
    }

    fn to_json_value(&self) -> serde_json::Value {
        serde_json::json!({
            "title": self.title,
            "artist": self.artist,
            "album": self.album,
            "track": self.track,
            "duration": self.duration,
            "bitrate": self.bitrate,
            "sample_rate": self.sample_rate,
            "path": self.path,
            "modified": self.modified,
            "created": self.created,
            "by": self.by
        })
    }

    /// 不支持：None  
    /// Lofty 能获取到信息：read_by_lofty  
    /// 不能的话：read_by_win_music_properties  
    /// 再不能的话：title: filename 代替
    fn read_from_path(path: impl AsRef<Path>) -> Option<Self> {
        let path = path.as_ref();
        let lofty_support: bool =
            *SUPPORT_FORMAT.get(&path.extension()?.to_ascii_lowercase().to_string_lossy())?;

        let file_metadata = match fs::metadata(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(err.to_string());
                return None;
            }
        };
        let modified = file_metadata
            .modified()
            .unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();
        let created = file_metadata
            .created()
            .unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();

        if lofty_support {
            if let Some(value) = Self::read_by_lofty(path, modified, created) {
                return Some(value);
            }

            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(value),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    return Self::new_with_path(path, None);
                }
            }
        } else {
            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(value),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    return Self::new_with_path(path, None);
                }
            }
        }
    }

    /// 使用 lofty 获取音乐标签。只在文件名不正确、没有标签或包含不支持的编码时返回 None
    fn read_by_lofty(path: impl AsRef<Path>, modified: u64, created: u64) -> Option<Self> {
        let path = path.as_ref();
        let tagged_file = match lofty::read_from_path(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", path, err));
                return None;
            }
        };

        let properties = tagged_file.properties();

        if let Some(tag) = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())
        {
            let artist_strs: Vec<_> = tag.get_strings(&ItemKey::TrackArtist).collect();
            let artist = if artist_strs.is_empty() {
                std::borrow::Cow::Borrowed("UNKNOWN").to_string()
            } else {
                artist_strs.join("/")
            };

            return Some(Audio {
                title: tag
                    .title()
                    .unwrap_or(path.file_name()?.to_string_lossy())
                    .to_string(),
                artist,
                album: tag
                    .album()
                    .unwrap_or(std::borrow::Cow::Borrowed("UNKNOWN"))
                    .to_string(),
                track: tag.track(),
                duration: properties.duration().as_secs(),
                bitrate: properties.audio_bitrate(),
                sample_rate: properties.sample_rate(),
                path: path.to_string_lossy().to_string(),
                modified,
                created,
                by: Some("Lofty".to_string()),
            });
        }

        return Some(Audio {
            title: path.file_name()?.to_string_lossy().to_string(),
            artist: std::borrow::Cow::Borrowed("UNKNOWN").to_string(),
            album: std::borrow::Cow::Borrowed("UNKNOWN").to_string(),
            track: None,
            duration: properties.duration().as_secs(),
            bitrate: properties.audio_bitrate(),
            sample_rate: properties.sample_rate(),
            path: path.to_string_lossy().to_string(),
            modified,
            created,
            by: Some("Lofty".to_string()),
        });
    }

    /// 使用 Windows Api 获取音乐标签。会因为各种原因返回 Err
    fn read_by_win_music_properties(
        path: impl AsRef<Path>,
        modified: u64,
        created: u64,
    ) -> Result<Self, windows::core::Error> {
        let path = path.as_ref();
        let storage_file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.get()?;
        let music_properties = storage_file
            .Properties()?
            .GetMusicPropertiesAsync()?
            .get()?;

        let duration: Duration = music_properties.Duration()?.into();

        let mut title = music_properties
            .Title()
            .or_else(|_| storage_file.Name())?
            .to_string();
        if title.is_empty() {
            title = storage_file.Name()?.to_string();
        }

        let mut artist = music_properties
            .Artist()
            .unwrap_or(HSTRING::from("UNKNOWN"))
            .to_string();
        if artist.is_empty() {
            artist = "UNKNOWN".to_string();
        }

        let mut album = music_properties
            .Album()
            .unwrap_or(HSTRING::from("UNKNOWN"))
            .to_string();
        if album.is_empty() {
            album = "UNKNOWN".to_string();
        }

        Ok(Audio {
            title,
            artist,
            album,
            track: Some(music_properties.TrackNumber()?),
            duration: duration.as_secs(),
            bitrate: Some(music_properties.Bitrate()? / 1000),
            sample_rate: None,
            path: path.to_string_lossy().to_string(),
            modified,
            created,
            by: Some("Windows".to_string()),
        })
    }
}

#[derive(Debug)]
struct AudioFolder {
    path: String,
    /// secs since UNIX_EPOCH
    modified: u64,
    /// biggest created in audios. secs since UNIX_EPOCH
    latest: u64,
    audios: Vec<Audio>,
}

fn read_directory_strictly(path: &Path) -> io::Result<fs::ReadDir> {
    fs::read_dir(path).map_err(|err| {
        log_to_dart(format!("{:?}: {}", path, err));
        err
    })
}

impl AudioFolder {
    fn to_json_value(&self) -> serde_json::Value {
        let mut audios_json: Vec<serde_json::Value> = vec![];
        for audio in &self.audios {
            audios_json.push(audio.to_json_value());
        }

        serde_json::json!({
            "path": self.path,
            "modified": self.modified,
            "latest": self.latest,
            "audios": audios_json,
        })
    }

    /// 扫描路径为 path 的文件夹
    fn read_from_folder(path: impl AsRef<Path>) -> Result<AudioFolder, io::Error> {
        let path = path.as_ref();

        let dir = match fs::read_dir(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", path, err));
                return Err(err);
            }
        };

        let mut audios: Vec<Audio> = vec![];
        let mut latest: u64 = 0;

        for item in dir {
            let entry = match item {
                Ok(value) => value,
                Err(_) => continue,
            };

            let file_type = match entry.file_type() {
                Ok(value) => value,
                Err(_) => continue,
            };

            if file_type.is_file() {
                if let Some(audio_item) = Audio::read_from_path(entry.path()) {
                    if audio_item.created > latest {
                        latest = audio_item.created;
                    }

                    audios.push(audio_item);
                }
            }
        }

        if !audios.is_empty() {
            return Ok(AudioFolder {
                path: path.to_string_lossy().to_string(),
                modified: fs::metadata(path)?
                    .modified()?
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs(),
                latest,
                audios,
            });
        }

        Err(io::Error::new(
            io::ErrorKind::NotFound,
            path.to_string_lossy() + " has no music.",
        ))
    }

    /// 扫描路径为 path 的文件夹及其所有子文件夹。
    fn read_from_folder_recursively(
        folder: impl AsRef<Path>,
        result: &mut Vec<Self>,
        scaned_count: &mut u64,
        total_count: &mut u64,
        scaned_folders: &mut HashSet<String>,
        sink: &StreamSink<IndexActionState>,
    ) -> Result<(), io::Error> {
        let folder = folder.as_ref();
        if scaned_folders.contains(&folder.to_string_lossy().to_string()) {
            return Ok(());
        }

        let dir = read_directory_strictly(folder)?;

        let _ = sink.add(IndexActionState {
            progress: *scaned_count as f64 / *total_count as f64,
            message: String::from("正在扫描 ") + &folder.to_string_lossy(),
        });

        scaned_folders.insert(folder.to_string_lossy().to_string());
        let mut audios: Vec<Audio> = vec![];
        let mut latest: u64 = 0;

        for item in dir {
            let entry = item.map_err(|err| {
                log_to_dart(err.to_string());
                err
            })?;

            let file_type = entry.file_type().map_err(|err| {
                log_to_dart(err.to_string());
                err
            })?;

            if file_type.is_dir() {
                *total_count += 1;
                Self::read_from_folder_recursively(
                    entry.path(),
                    result,
                    scaned_count,
                    total_count,
                    scaned_folders,
                    sink,
                )?;
            } else if let Some(metadata) = Audio::read_from_path(entry.path()) {
                if metadata.created > latest {
                    latest = metadata.created;
                }

                audios.push(metadata);
            }
        }

        if !audios.is_empty() {
            let metadata = fs::metadata(folder).map_err(|err| {
                log_to_dart(format!("{:?}: {}", folder, err));
                err
            })?;
            let modified = metadata.modified().map_err(|err| {
                log_to_dart(format!("{:?}: {}", folder, err));
                err
            })?;
            result.push(AudioFolder {
                path: folder.to_string_lossy().to_string(),
                modified: modified
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs(),
                latest,
                audios,
            });
        }

        *scaned_count += 1;
        let _ = sink.add(IndexActionState {
            progress: *scaned_count as f64 / *total_count as f64,
            message: String::new(),
        });

        Ok(())
    }
}

fn _get_picture_by_windows(path: &String) -> Result<Vec<u8>, windows::core::Error> {
    let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.get()?;
    let thumbnail = file
        .GetThumbnailAsyncOverloadDefaultSizeDefaultOptions(ThumbnailMode::MusicView)?
        .get()?;

    let size = thumbnail.Size()? as u32;
    let stream: IInputStream = thumbnail.cast()?;

    let mut buffer = vec![0u8; size as usize];
    let data_reader = DataReader::CreateDataReader(&stream)?;
    data_reader.LoadAsync(size)?.get()?;
    data_reader.ReadBytes(&mut buffer)?;

    data_reader.Close()?;
    stream.Close()?;

    Ok(buffer)
}

fn _get_picture_by_lofty(path: &String) -> Option<Vec<u8>> {
    if let Ok(tagged_file) = lofty::read_from_path(&path) {
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())?;

        return Some(tag.pictures().first()?.data().to_vec());
    }

    None
}

/// for Flutter  
/// 如果无法通过 Lofty 获取则通过 Windows 获取
pub fn get_picture_from_path(path: String, width: u32, height: u32) -> Option<Vec<u8>> {
    let pic_option =
        _get_picture_by_lofty(&path).or_else(|| match _get_picture_by_windows(&path) {
            Ok(val) => Some(val),
            Err(err) => {
                log_to_dart(format!("fail to get pic: {}", err));
                None
            }
        });

    if let Some(pic) = &pic_option {
        if let Ok(loaded_pic) = image::load_from_memory(pic) {
            // 计算新的宽高，保持原比例
            let pic_ratio = loaded_pic.width() as f32 / loaded_pic.height() as f32;

            let (result_width, result_height) = if pic_ratio > 1.0 {
                (width, (width as f32 / pic_ratio).round() as u32)
            } else {
                ((height as f32 * pic_ratio).round() as u32, height)
            };

            let resized_img = imageops::resize(
                &loaded_pic,
                result_width,
                result_height,
                imageops::FilterType::Triangle,
            );

            let mut output = Cursor::new(Vec::new());
            if let Ok(_) = resized_img.write_to(&mut output, image::ImageFormat::Png) {
                return Some(output.into_inner());
            }
        }
    }

    pic_option
}

fn parse_ttml_timestamp(value: &str) -> Option<f64> {
    let value = value.trim();
    let parts: Vec<_> = value.split(':').collect();
    let seconds = match parts.as_slice() {
        [seconds] => {
            let seconds = seconds.parse::<f64>().ok()?;
            if !seconds.is_finite() || seconds < 0.0 {
                return None;
            }
            seconds
        }
        [minutes, seconds] => {
            // Match Ttml._parseTimestamp: minutes are an integer and may be
            // larger than 59; only the seconds component is bounded.
            let minutes = minutes.parse::<u64>().ok()? as f64;
            let seconds = seconds.parse::<f64>().ok()?;
            if !seconds.is_finite() || !(0.0..60.0).contains(&seconds) {
                return None;
            }
            minutes * 60.0 + seconds
        }
        [hours, minutes, seconds] => {
            let hours = hours.parse::<u64>().ok()? as f64;
            let minutes = minutes.parse::<u64>().ok()?;
            let seconds = seconds.parse::<f64>().ok()?;
            if minutes >= 60 || !seconds.is_finite() || !(0.0..60.0).contains(&seconds) {
                return None;
            }
            hours * 3600.0 + minutes as f64 * 60.0 + seconds
        }
        _ => return None,
    };
    (seconds.is_finite() && seconds >= 0.0).then_some(seconds)
}

fn ttml_attribute<'a>(opening: &'a str, name: &str) -> Option<&'a str> {
    let mut offset = 0;
    while let Some(relative_start) = opening[offset..].find(name) {
        let start = offset + relative_start;
        let end = start + name.len();
        let is_name_boundary = opening[..start].chars().last().map_or(true, |character| {
            !(character.is_ascii_alphanumeric() || matches!(character, '_' | ':' | '-'))
        });
        if !is_name_boundary {
            offset = end;
            continue;
        }

        let mut cursor = end;
        while let Some(character) = opening[cursor..].chars().next() {
            if !character.is_whitespace() {
                break;
            }
            cursor += character.len_utf8();
        }
        if opening.as_bytes().get(cursor) != Some(&b'=') {
            offset = end;
            continue;
        }
        cursor += 1;
        while let Some(character) = opening[cursor..].chars().next() {
            if !character.is_whitespace() {
                break;
            }
            cursor += character.len_utf8();
        }
        let Some(quote) = opening[cursor..].chars().next() else {
            return None;
        };
        if quote != '\'' && quote != '"' {
            offset = end;
            continue;
        }
        let value_start = cursor + quote.len_utf8();
        return opening[value_start..]
            .find(quote)
            .map(|relative_end| &opening[value_start..value_start + relative_end]);
    }
    None
}

fn has_visible_xml_text(value: &str) -> bool {
    let mut visible = false;
    let mut in_tag = false;
    let mut in_comment = false;
    let mut chars = value.chars().peekable();
    while let Some(character) = chars.next() {
        if in_comment {
            if character == '-' && chars.peek() == Some(&'-') {
                chars.next();
                if chars.next() == Some('>') {
                    in_comment = false;
                }
            }
        } else if character == '<' && chars.peek() == Some(&'!') {
            chars.next();
            if chars.next() == Some('-') && chars.next() == Some('-') {
                in_comment = true;
            }
        } else if character == '<' {
            in_tag = true;
        } else if character == '>' && in_tag {
            in_tag = false;
        } else if !in_tag && !character.is_whitespace() {
            visible = true;
        }
    }
    visible
}

fn strip_xml_ignored_nodes(xml: &str) -> String {
    let mut result = String::with_capacity(xml.len());
    let mut remaining = xml;
    loop {
        let mut next: Option<(usize, &str, &str)> = None;
        for (start_marker, end_marker) in [
            ("<!--", "-->"),
            ("<?", "?>"),
            ("<![cdata[", "]]>")
        ] {
            if let Some(start) = remaining.find(start_marker) {
                if next.map_or(true, |(old_start, _, _)| start < old_start) {
                    next = Some((start, start_marker, end_marker));
                }
            }
        }
        let Some((start, start_marker, end_marker)) = next else {
            break;
        };
        result.push_str(&remaining[..start]);
        let content_start = start + start_marker.len();
        let Some(end) = remaining[content_start..].find(end_marker) else {
            // Ignore an unterminated comment/PI/CDATA rather than scanning
            // markup inside it as a real element.
            remaining = "";
            break;
        };
        let content = &remaining[content_start..content_start + end];
        if start_marker == "<![cdata[" {
            // CDATA is text to the Dart XML parser. Avoid treating literal
            // '<p>' inside that text as a real paragraph while retaining its
            // non-markup characters for visible-text detection.
            result.extend(content.chars().map(|character| {
                if character == '<' { ' ' } else { character }
            }));
        }
        remaining = &remaining[content_start + end + end_marker.len()..];
    }
    result.push_str(remaining);
    result
}

fn has_valid_ttml_paragraph(xml: &str) -> bool {
    let xml = strip_xml_ignored_nodes(xml);
    xml.match_indices('<').any(|(start, _)| {
        let rest = &xml[start + 1..];
        if rest.starts_with('/') {
            return false;
        }
        let Some(end) = rest.find('>') else {
            return false;
        };
        let opening = &rest[..end];
        let name = opening
            .split_whitespace()
            .next()
            .unwrap_or("")
            .trim_end_matches('/');
        if name != "p" && !name.ends_with(":p") {
            return false;
        }
        let Some(begin) = ttml_attribute(opening, "begin").and_then(parse_ttml_timestamp) else {
            return false;
        };
        let timing_valid = if let Some(end_value) = ttml_attribute(opening, "end") {
            // Dart's _resolveEnd gives an explicit end precedence over dur;
            // an invalid or reversed end must not be replaced by dur.
            parse_ttml_timestamp(end_value).map_or(false, |value| value > begin)
        } else {
            ttml_attribute(opening, "dur")
                .and_then(parse_ttml_timestamp)
                .map_or(false, |value| value > 0.0)
        };
        let closing = format!("</{}>", name);
        let Some(close) = xml[start + end + 2..].find(&closing) else {
            return false;
        };
        let visible_text = &xml[start + end + 2..start + end + 2 + close];
        timing_valid && has_visible_xml_text(visible_text)
    })
}

fn select_lyric_text(
    candidates: impl IntoIterator<Item = (String, String)>,
) -> Option<String> {
    candidates.into_iter().find_map(|(key, text)| {
        let normalized_key = key.to_lowercase();
        if normalized_key != "lyrics" && normalized_key != "lyric" {
            return None;
        }

        let trimmed = text.trim();
        let mut ttml_source = trimmed.trim_start_matches('\u{feff}').trim_start();
        while ttml_source.starts_with("<?") {
            let Some(end) = ttml_source.find("?>") else {
                break;
            };
            ttml_source = ttml_source[end + 2..].trim_start();
        }
        let lowered = ttml_source.to_lowercase();
        let root_name = lowered
            .strip_prefix('<')
            .and_then(|source| source.split(|character: char| character.is_whitespace() || character == '>').next())
            .unwrap_or("");
        let root_is_tt = root_name == "tt"
            || root_name
                .rsplit_once(':')
                .map_or(false, |(_, local_name)| local_name == "tt");
        let body_name = lowered.match_indices('<').find_map(|(start, _)| {
            let token = lowered[start + 1..]
                .split(|character: char| character.is_whitespace() || character == '>')
                .next()
                .unwrap_or("");
            (token == "body" || token.ends_with(":body")).then_some(token)
        });
        let body_content_nonempty = body_name.map_or(false, |body| {
            lowered
                .find(&format!("<{}", body))
                .and_then(|start| {
                    lowered[start..].find('>').and_then(|end| {
                        lowered[start + end + 1..]
                            .find(&format!("</{}>", body))
                            .map(|body_end| body_end > 0)
                    })
                })
                .unwrap_or(false)
        });
        let looks_like_ttml = root_is_tt
            && lowered.contains(&format!("</{}>", root_name))
            && body_content_nonempty
            && has_valid_ttml_paragraph(&lowered);
        let looks_like_lrc = trimmed.lines().any(|line| {
            let mut remaining = line;
            while let Some(start) = remaining.find('[') {
                let after_open = &remaining[start + 1..];
                let Some(end) = after_open.find(']') else {
                    break;
                };
                let timestamp = &after_open[..end];
                if let Some((minutes, seconds)) = timestamp.split_once(':') {
                    let valid_minutes = minutes.parse::<u64>().is_ok();
                    let valid_seconds = seconds
                        .parse::<f64>()
                        .map_or(false, |value| value.is_finite() && (0.0..60.0).contains(&value));
                    if valid_minutes && valid_seconds {
                        return true;
                    }
                }
                remaining = &after_open[end + 1..];
            }
            false
        });
        (looks_like_ttml || looks_like_lrc).then_some(text)
    })
}

fn _get_lyric_from_lofty(path: &String) -> Option<String> {
    if let Ok(tagged_file) = lofty::read_from_path(&path) {
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())?;
        let mut candidates = Vec::new();
        if let Some(lyric) = tag.get(&ItemKey::Lyrics).and_then(|item| item.value().text()) {
            candidates.push(("Lyrics".to_string(), lyric.to_string()));
        }
        for item in tag.items() {
            if let ItemKey::Unknown(key) = item.key() {
                if let Some(text) = item.value().text() {
                    candidates.push((key.to_string(), text.to_string()));
                }
            }
        }
        return select_lyric_text(candidates);
    }

    None
}

fn _get_lyric_from_lrc_file(path: &String) -> anyhow::Result<String> {
    let mut lrc_file_path = PathBuf::from(path);
    lrc_file_path.set_extension("lrc");

    let lrc_bytes = fs::read(lrc_file_path)?;

    let is_le = lrc_bytes.starts_with(&[0xFF, 0xFE]);
    let is_utf16 = (is_le || lrc_bytes.starts_with(&[0xFE, 0xFF])) && lrc_bytes.len() % 2 == 0;

    if is_utf16 {
        let convert_fn = match is_le {
            true => u16::from_le_bytes,
            false => u16::from_be_bytes,
        };

        let mut u16_bytes: Vec<u16> = vec![];
        let mut chunk_iter = lrc_bytes.chunks_exact(2);
        chunk_iter.next();

        for chunk in chunk_iter {
            u16_bytes.push(convert_fn([chunk[0], chunk[1]]));
        }
        return Ok(String::from_utf16(&u16_bytes)?);
    }

    return Ok(String::from_utf8(lrc_bytes)?);
}

/// for Flutter   
/// 只支持读取 ID3V2, VorbisComment, Mp4Ilst 存储的内嵌歌词
/// 以及相同目录相同文件名的 .lrc 外挂歌词（utf-8 or utf-16）
pub fn get_lyric_from_path(path: String) -> Option<String> {
    return _get_lyric_from_lofty(&path).or_else(|| match _get_lyric_from_lrc_file(&path) {
        Ok(val) => Some(val),
        Err(err) => {
            log_to_dart(format!("fail to get lrc: {}", err.to_string()));
            None
        }
    });
}

/// for Flutter  
/// 扫描给定路径下所有子文件夹（包括自己）的音乐文件并把索引保存在 index_path/index.json。
pub fn build_index_from_folders_recursively(
    folders: Vec<String>,
    index_path: String,
    sink: StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    with_valid_scan_roots(&folders, || {
        let mut audio_folders: Vec<AudioFolder> = vec![];
        let mut scaned: u64 = 0;
        let mut total: u64 = folders.len() as u64;
        let mut scaned_folders: HashSet<String> = HashSet::new();

        for item in &folders {
            AudioFolder::read_from_folder_recursively(
                Path::new(item),
                &mut audio_folders,
                &mut scaned,
                &mut total,
                &mut scaned_folders,
                &sink,
            )?;
        }

        let mut audio_folders_json: Vec<serde_json::Value> = vec![];
        for item in &audio_folders {
            audio_folders_json.push(item.to_json_value());
        }
        let normalized_roots: Vec<String> = folders
            .iter()
            .filter_map(|folder| normalize_index_path(Path::new(folder)).ok())
            .collect();
        let json_value = serde_json::json!({
            "version": 110,
            "roots": normalized_roots,
            "folders": audio_folders_json,
        });

        let mut index_path = PathBuf::from(index_path);
        index_path.push("index.json");
        write_index_atomically(&index_path, &json_value)?;

        Ok(())
    })
}

fn with_valid_scan_roots<T>(
    folders: &[String],
    build: impl FnOnce() -> io::Result<T>,
) -> io::Result<T> {
    if folders.is_empty() || folders.iter().any(|folder| folder.trim().is_empty()) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "at least one non-empty scan root is required",
        ));
    }
    build()
}

fn normalize_index_path(path: &Path) -> io::Result<String> {
    let absolute = fs::canonicalize(path).or_else(|_| {
        if path.is_absolute() {
            Ok(path.to_path_buf())
        } else {
            std::env::current_dir().map(|current| current.join(path))
        }
    })?;
    let value = absolute.to_string_lossy().to_string();
    Ok(if cfg!(windows) {
        value.to_ascii_lowercase()
    } else {
        value
    })
}

fn write_index_atomically(index_path: &Path, value: &serde_json::Value) -> io::Result<()> {
    let parent = index_path.parent().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "index path has no parent")
    })?;
    fs::create_dir_all(parent)?;
    let temporary = index_path.with_extension("json.tmp");
    let backup = index_path.with_extension("json.bak");
    fs::File::create(&temporary)?.write_all(value.to_string().as_bytes())?;

    let moved_current = if index_path.exists() {
        if backup.exists() {
            fs::remove_file(&backup)?;
        }
        fs::rename(index_path, &backup)?;
        true
    } else {
        false
    };
    if let Err(error) = fs::rename(&temporary, index_path) {
        if moved_current && backup.exists() {
            let _ = fs::remove_file(index_path);
            let _ = fs::rename(&backup, index_path);
        }
        return Err(error);
    }
    if moved_current && backup.exists() {
        let _ = fs::remove_file(backup);
    }
    Ok(())
}

/// ABI compatibility wrapper for older generated Flutter bindings.
///
/// Production Dart code does not call this function. If invoked by an older
/// client, it reads only the explicitly stored roots and performs the same
/// complete recursive rebuild as `build_index_from_folders_recursively`.
pub fn update_index(index_path: String, sink: StreamSink<IndexActionState>) -> anyhow::Result<()> {
    let bytes = fs::read(PathBuf::from(&index_path).join("index.json"))?;
    let existing_index: serde_json::Value = serde_json::from_slice(&bytes)?;
    let roots: Vec<String> = existing_index["roots"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|value| value.as_str().map(String::from))
        .collect();
    if roots.is_empty() {
        return Err(anyhow::anyhow!(
            "index is missing configured scan roots; select folders before rebuilding"
        ));
    }
    build_index_from_folders_recursively(roots, index_path, sink)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lyric_alias_prefers_the_first_timed_value() {
        let candidates = vec![
            ("Lyrics".to_string(), "plain description".to_string()),
            ("LYRIC".to_string(), "[00:01.00]valid lyric".to_string()),
        ];

        assert_eq!(
            select_lyric_text(candidates),
            Some("[00:01.00]valid lyric".to_string())
        );
    }

    #[test]
    fn lyric_alias_rejects_colons_outside_a_timestamp_bracket() {
        let candidates = vec![
            (
                "LYRICS".to_string(),
                "[description] notes: value]".to_string(),
            ),
            ("LYRIC".to_string(), "[00:02.00]valid lyric".to_string()),
        ];

        assert_eq!(
            select_lyric_text(candidates),
            Some("[00:02.00]valid lyric".to_string())
        );
    }

    #[test]
    fn lyric_alias_scans_past_non_timestamp_brackets() {
        let candidates = vec![(
            "LYRICS".to_string(),
            "[Chorus]\n[00:01.00]valid lyric".to_string(),
        )];

        assert_eq!(
            select_lyric_text(candidates),
            Some("[Chorus]\n[00:01.00]valid lyric".to_string())
        );
    }

    #[test]
    fn lyric_alias_rejects_metadata_and_invalid_ttml() {
        let candidates = vec![
            ("Lyrics".to_string(), "[ti:Song]".to_string()),
            ("LYRIC".to_string(), "<not-ttml".to_string()),
            ("LYRICS".to_string(), "[00:03.00]valid lyric".to_string()),
        ];

        assert_eq!(
            select_lyric_text(candidates),
            Some("[00:03.00]valid lyric".to_string())
        );
    }

    #[test]
    fn lyric_alias_accepts_xml_declaration_bom_and_namespaced_ttml() {
        let candidates = vec![(
            "Lyrics".to_string(),
            "\u{feff}<?xml version=\"1.0\"?><ly:tt xmlns:ly=\"urn:ttml\"><ly:body><ly:p begin=\"1\" end=\"2\">valid</ly:p></ly:body></ly:tt>".to_string(),
        )];

        assert_eq!(select_lyric_text(candidates).is_some(), true);
    }

    #[test]
    fn lyric_alias_rejects_empty_ttml_and_falls_through() {
        let candidates = vec![
            (
                "Lyrics".to_string(),
                "<tt><body></body></tt>".to_string(),
            ),
            ("LYRIC".to_string(), "[00:04.00]valid lyric".to_string()),
        ];

        assert_eq!(
            select_lyric_text(candidates),
            Some("[00:04.00]valid lyric".to_string())
        );
    }

    #[test]
    fn lyric_alias_rejects_structurally_empty_ttml_and_falls_through() {
        let candidates = vec![
            ("Lyrics".to_string(), "<tt><body> </body></tt>".to_string()),
            ("LYRIC".to_string(), "<tt><body><div/></body></tt>".to_string()),
            (
                "LYRICS".to_string(),
                "<tt><body><p begin=\"1\">valid</p></body></tt>".to_string(),
            ),
            ("LYRIC".to_string(), "[00:05.00]valid lyric".to_string()),
        ];

        assert_eq!(
            select_lyric_text(candidates),
            Some("[00:05.00]valid lyric".to_string())
        );
    }

    #[test]
    fn lyric_alias_accepts_dart_timestamp_forms_and_single_quoted_attributes() {
        let candidates = vec![
            (
                "Lyrics".to_string(),
                "<tt><body><p begin = '00:01' end = '00:02'><span></span></p></body></tt>"
                    .to_string(),
            ),
            (
                "LYRIC".to_string(),
                "<tt><body><p begin=\"57.085\" end=\"1:03.351\">valid</p></body></tt>"
                    .to_string(),
            ),
        ];

        assert_eq!(
            select_lyric_text(candidates),
            Some("<tt><body><p begin=\"57.085\" end=\"1:03.351\">valid</p></body></tt>".to_string())
        );
    }

    #[test]
    fn lyric_alias_accepts_single_quoted_ttml_attributes() {
        let lyric = "<tt><body><p begin = '00:01' end = '00:02'>valid</p></body></tt>";

        assert_eq!(select_lyric_text(vec![("LYRIC".to_string(), lyric.to_string())]), Some(lyric.to_string()));
    }

    #[test]
    fn lyric_alias_rejects_out_of_range_and_commented_ttml_timestamps() {
        let candidates = vec![
            ("Lyrics".to_string(), "[00:61]metadata".to_string()),
            (
                "LYRIC".to_string(),
                "<tt><body><!-- <p begin=\"1\" end=\"2\">hidden</p> --></body></tt>"
                    .to_string(),
            ),
            ("LYRICS".to_string(), "[00:61]metadata".to_string()),
            ("LYRIC".to_string(), "[00:06.00]valid lyric".to_string()),
        ];

        assert_eq!(
            select_lyric_text(candidates),
            Some("[00:06.00]valid lyric".to_string())
        );
    }

    #[test]
    fn lyric_alias_matches_dart_ttml_time_rules_and_end_precedence() {
        let candidates = vec![
            (
                "Lyrics".to_string(),
                "<tt><body><p begin=\"00:61\" end=\"00:62\">bad</p></body></tt>"
                    .to_string(),
            ),
            (
                "LYRIC".to_string(),
                "<tt><body><p begin=\"2\" end=\"1\" dur=\"3\">bad</p></body></tt>"
                    .to_string(),
            ),
            (
                "LYRICS".to_string(),
                "<tt><body><p begin=\"60:00\" end=\"60:01\">valid</p></body></tt>"
                    .to_string(),
            ),
        ];

        assert_eq!(
            select_lyric_text(candidates),
            Some(
                "<tt><body><p begin=\"60:00\" end=\"60:01\">valid</p></body></tt>"
                    .to_string()
            )
        );
    }

    #[test]
    fn empty_scan_roots_are_rejected_before_an_existing_index_is_touched() {
        let directory = std::env::temp_dir().join(format!(
            "coriander-empty-roots-{}",
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&directory).unwrap();
        let index_path = directory.join("index.json");
        let existing = br#"{"version":110,"roots":["D:/Music"],"folders":[]}"#;
        fs::write(&index_path, existing).unwrap();

        let error = with_valid_scan_roots(&[], || {
            fs::write(&index_path, b"overwritten")?;
            Ok(())
        })
        .unwrap_err();

        assert_eq!(error.kind(), io::ErrorKind::InvalidInput);
        assert_eq!(fs::read(&index_path).unwrap(), existing);
        fs::remove_dir_all(directory).unwrap();
    }
}
