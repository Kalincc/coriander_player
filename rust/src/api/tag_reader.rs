use std::{
    collections::{BTreeMap, HashMap, HashSet},
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
            "size": fs::metadata(&self.path).map(|metadata| metadata.len()).unwrap_or(0),
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

        let dir = match fs::read_dir(folder) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", folder, err));
                return Ok(());
            }
        };

        let _ = sink.add(IndexActionState {
            progress: *scaned_count as f64 / *total_count as f64,
            message: String::from("正在扫描 ") + &folder.to_string_lossy(),
        });

        scaned_folders.insert(folder.to_string_lossy().to_string());
        let mut audios: Vec<Audio> = vec![];
        let mut latest: u64 = 0;

        for item in dir {
            let entry = match item {
                Ok(value) => value,
                Err(err) => {
                    log_to_dart(err.to_string());
                    continue;
                }
            };

            let file_type = match entry.file_type() {
                Ok(value) => value,
                Err(err) => {
                    log_to_dart(err.to_string());
                    continue;
                }
            };

            if file_type.is_dir() {
                *total_count += 1;
                let _ = Self::read_from_folder_recursively(
                    entry.path(),
                    result,
                    scaned_count,
                    total_count,
                    scaned_folders,
                    sink,
                );
            } else if let Some(metadata) = Audio::read_from_path(entry.path()) {
                if metadata.created > latest {
                    latest = metadata.created;
                }

                audios.push(metadata);
            }
        }

        if !audios.is_empty() {
            if let Ok(metadata) = fs::metadata(folder) {
                if let Ok(modified) = metadata.modified() {
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
            }
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

fn _get_lyric_from_lofty(path: &String) -> Option<String> {
    if let Ok(tagged_file) = lofty::read_from_path(&path) {
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())?;
        let lyric_tag = tag.get(&ItemKey::Lyrics)?;
        let lyric = lyric_tag.value().text()?;

        return Some(lyric.to_string());
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
    let mut audio_folders: Vec<AudioFolder> = vec![];
    let mut scaned: u64 = 0;
    let mut total: u64 = folders.len() as u64;
    let mut scaned_folders: HashSet<String> = HashSet::new();

    for item in &folders {
        let _ = AudioFolder::read_from_folder_recursively(
            Path::new(item),
            &mut audio_folders,
            &mut scaned,
            &mut total,
            &mut scaned_folders,
            &sink,
        );
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
}

fn _update_index_below_1_1_0(
    index: &serde_json::Value,
    index_path: &PathBuf,
    sink: &StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    let mut audio_folders_json: Vec<serde_json::Value> = vec![];
    let folders = index.as_array().unwrap();
    for item in folders {
        let path = item["path"].as_str().unwrap();
        let _ = sink.add(IndexActionState {
            progress: audio_folders_json.len() as f64 / folders.len() as f64,
            message: String::from("正在扫描 ") + path,
        });
        let folder_path = Path::new(path);
        if let Ok(audio_folder) = AudioFolder::read_from_folder(folder_path) {
            audio_folders_json.push(audio_folder.to_json_value());
            let _ = sink.add(IndexActionState {
                progress: audio_folders_json.len() as f64 / folders.len() as f64,
                message: String::new(),
            });
        }
    }
    fs::File::create(index_path)?.write_all(
        serde_json::json!({
            "version": 110,
            "folders": audio_folders_json,
        })
        .to_string()
        .as_bytes(),
    )?;

    Ok(())
}

/// for Flutter   
/// 读取 index_path/index.json，检查更新。不可能重新读取被修改的文件夹下所有的音乐标签，这样太耗时。  
///
/// [LOWEST_VERSION] 指定可以继承的 index 的最低版本。
/// 如果 index version < [LOWEST_VERSION] 或者是 index 根本没有 version 再或者格式不符合要求，就转到
/// [_update_index_below_1_1_0] 更新 index；
/// 如果 index version >= [LOWEST_VERSION] 则进行更新。
///
/// 如果文件夹不存在，删除记录。  
/// 如果文件夹被修改（再次读取到的 modified > 记录的 modified），就更新它。没有则跳过它
/// 1. 遍历该文件夹索引，判断文件是否存在，不存在则删除记录
/// 2. 遍历该文件夹索引，如果文件被修改（再次读取到的 modified > 记录的 modified），重新读取标签；没有则跳过它
/// 3. 遍历该文件夹，添加新增（读取到的 created > 记录的 latest）的音乐文件
fn legacy_update_index(index_path: String, sink: StreamSink<IndexActionState>) -> anyhow::Result<()> {
    let mut index_path = PathBuf::from(index_path);
    index_path.push("index.json");
    let index = fs::read(&index_path)?;
    let mut index: serde_json::Value = serde_json::from_slice(&index)?;

    let version = index["version"].as_u64();
    if version.is_none() {
        return Ok(_update_index_below_1_1_0(&index, &index_path, &sink)?);
    }

    let folders = index["folders"].as_array_mut().unwrap();
    // 删除访问不到的文件夹的记录
    folders.retain(|item| {
        let path = item["path"].as_str().unwrap();

        Path::new(path).exists()
    });

    let mut updated = 0;
    let total = folders.len();

    for folder_item in folders {
        let folder_path = folder_item["path"].as_str().unwrap().to_string();
        let latest = folder_item["latest"].as_u64().unwrap();
        let old_folder_modified = folder_item["modified"].as_u64().unwrap();

        let new_folder_modified = match fs::metadata(&folder_path) {
            Ok(value) => match value.modified() {
                Ok(value) => value
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs(),
                Err(_) => continue,
            },
            Err(_) => continue,
        };

        // 跳过没有被修改的文件夹
        if new_folder_modified <= old_folder_modified {
            updated += 1;
            continue;
        }

        let _ = sink.add(IndexActionState {
            progress: updated as f64 / total as f64,
            message: String::from("正在更新 ") + &folder_path,
        });

        folder_item["modified"] = serde_json::json!(new_folder_modified);

        // 删除访问不到的文件的记录
        let audios = folder_item["audios"].as_array_mut().unwrap();
        audios.retain(|item| {
            let path = item["path"].as_str().unwrap();

            Path::new(path).exists()
        });

        for audio_item in &mut *audios {
            let old_audio_modified = audio_item["modified"].as_u64().unwrap();
            let audio_path = audio_item["path"].as_str().unwrap();
            let new_audio_modified = match fs::metadata(&audio_path) {
                Ok(value) => match value.modified() {
                    Ok(value) => value
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or(Duration::ZERO)
                        .as_secs(),
                    Err(_) => continue,
                },
                Err(_) => continue,
            };
            // 跳过没有被修改的文件
            if new_audio_modified <= old_audio_modified {
                continue;
            }

            // 重新读取被修改的音乐文件的标签并更新
            if let Some(modified_audio) = Audio::read_from_path(Path::new(audio_path)) {
                *audio_item = modified_audio.to_json_value();
            }
        }

        // 添加新增的音乐文件
        let mut new_latest: u64 = latest;
        let dir = match fs::read_dir(folder_path) {
            Ok(value) => value,
            Err(_) => continue,
        };
        for entry in dir {
            let entry = match entry {
                Ok(value) => value,
                Err(_) => continue,
            };
            let file_type = match entry.file_type() {
                Ok(value) => value,
                Err(_) => continue,
            };
            if file_type.is_dir() {
                continue;
            }

            let entry_created = match entry.metadata() {
                Ok(value) => match value.created() {
                    Ok(value) => value
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or(Duration::ZERO)
                        .as_secs(),
                    Err(_) => continue,
                },
                Err(_) => continue,
            };
            if entry_created > latest {
                if let Some(new_audio) = Audio::read_from_path(entry.path()) {
                    if entry_created > new_latest {
                        new_latest = entry_created;
                    }

                    audios.push(new_audio.to_json_value());
                }
            }
        }

        folder_item["latest"] = serde_json::json!(new_latest);

        updated += 1;
        let _ = sink.add(IndexActionState {
            progress: updated as f64 / total as f64,
            message: String::new(),
        });
    }

    fs::File::create(index_path)?.write_all(index.to_string().as_bytes())?;

    Ok(())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct FileFingerprint {
    modified: u64,
    size: Option<u64>,
}

impl FileFingerprint {
    fn from_path(path: &Path) -> io::Result<Self> {
        let metadata = fs::metadata(path)?;
        Ok(Self {
            modified: metadata
                .modified()?
                .duration_since(UNIX_EPOCH)
                .unwrap_or(Duration::ZERO)
                .as_secs(),
            size: Some(metadata.len()),
        })
    }

    fn matches(self, current: Self) -> bool {
        self.modified == current.modified
            && self.size.map(|size| Some(size) == current.size).unwrap_or(true)
    }
}

#[derive(Default)]
struct PathChanges {
    added: Vec<String>,
    removed: Vec<String>,
    modified: Vec<String>,
    unchanged: Vec<String>,
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

fn is_supported_audio_path(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| SUPPORT_FORMAT.contains_key(&extension.to_ascii_lowercase()))
        .unwrap_or(false)
}

fn scan_audio_paths(roots: &[PathBuf]) -> io::Result<BTreeMap<String, PathBuf>> {
    let mut scanned = BTreeMap::new();
    let mut visited = HashSet::new();
    for root in roots {
        scan_directory_recursively(root, &mut visited, &mut scanned)?;
    }
    Ok(scanned)
}

fn scan_directory_recursively(
    directory: &Path,
    visited: &mut HashSet<String>,
    scanned: &mut BTreeMap<String, PathBuf>,
) -> io::Result<()> {
    let normalized = normalize_index_path(directory).map_err(|error| {
        log_to_dart(format!("{:?}: {}", directory, error));
        error
    })?;
    if !visited.insert(normalized) {
        return Ok(());
    }

    let entries = fs::read_dir(directory).map_err(|error| {
        log_to_dart(format!("{:?}: {}", directory, error));
        error
    })?;
    for entry in entries {
        let entry = entry.map_err(|error| {
            log_to_dart(error.to_string());
            error
        })?;
        let path = entry.path();
        let file_type = entry.file_type().map_err(|error| {
            log_to_dart(error.to_string());
            error
        })?;
        match file_type {
            file_type if file_type.is_dir() => {
                scan_directory_recursively(&path, visited, scanned)?;
            }
            file_type if file_type.is_file() && is_supported_audio_path(&path) => {
                let normalized = normalize_index_path(&path).map_err(|error| {
                    log_to_dart(format!("{:?}: {}", path, error));
                    error
                })?;
                scanned.insert(normalized, path);
            }
            _ => {}
        }
    }
    Ok(())
}

fn classify_path_changes(
    scanned: &BTreeMap<String, PathBuf>,
    existing: &HashMap<String, FileFingerprint>,
) -> PathChanges {
    let mut changes = PathChanges::default();
    for (path, disk_path) in scanned {
        match existing.get(path) {
            None => changes.added.push(path.clone()),
            Some(existing_fingerprint) => match FileFingerprint::from_path(disk_path) {
                Ok(fingerprint) if existing_fingerprint.matches(fingerprint) => {
                    changes.unchanged.push(path.clone())
                }
                Ok(_) | Err(_) => changes.modified.push(path.clone()),
            },
        }
    }
    for path in existing.keys() {
        if !scanned.contains_key(path) {
            changes.removed.push(path.clone());
        }
    }
    changes
}

fn configured_roots_from_index(index: &serde_json::Value) -> anyhow::Result<Vec<PathBuf>> {
    let configured = index["roots"].as_array().into_iter().flatten();
    let roots: Vec<PathBuf> = configured
        .filter_map(|value| value.as_str())
        .map(PathBuf::from)
        .collect();
    if !roots.is_empty() {
        return Ok(roots);
    }
    Err(anyhow::anyhow!(
        "index is missing configured scan roots; rebuild the library from folder management"
    ))
}

fn existing_audio_records(index: &serde_json::Value) -> HashMap<String, serde_json::Value> {
    let folders = if let Some(folders) = index.as_array() {
        folders
    } else {
        index["folders"].as_array().map(Vec::as_slice).unwrap_or(&[])
    };
    folders
        .iter()
        .flat_map(|folder| folder["audios"].as_array().into_iter().flatten())
        .filter_map(|audio| {
            let path = audio["path"].as_str()?;
            Some((normalize_index_path(Path::new(path)).ok()?, audio.clone()))
        })
        .collect()
}

fn existing_fingerprints(
    records: &HashMap<String, serde_json::Value>,
) -> HashMap<String, FileFingerprint> {
    records
        .iter()
        .filter_map(|(path, audio)| {
            Some((
                path.clone(),
                FileFingerprint {
                    modified: audio["modified"].as_u64()?,
                    size: audio["size"].as_u64(),
                },
            ))
        })
        .collect()
}

fn with_current_size(
    mut record: serde_json::Value,
    disk_path: &Path,
) -> serde_json::Value {
    if let Ok(fingerprint) = FileFingerprint::from_path(disk_path) {
        record["size"] = serde_json::json!(fingerprint.size.unwrap_or(0));
    }
    record
}

fn build_incremental_index(
    roots: &[PathBuf],
    existing_index: &serde_json::Value,
    sink: &StreamSink<IndexActionState>,
) -> io::Result<serde_json::Value> {
    for root in roots {
        let _ = sink.add(IndexActionState {
            progress: 0.0,
            message: String::from("正在扫描 ") + &root.to_string_lossy(),
        });
    }
    let scanned = scan_audio_paths(roots)?;
    let existing = existing_audio_records(existing_index);
    let fingerprints = existing_fingerprints(&existing);
    let changes = classify_path_changes(&scanned, &fingerprints);
    let changed: HashSet<&str> = changes
        .added
        .iter()
        .chain(changes.modified.iter())
        .map(String::as_str)
        .collect();
    let total = scanned.len().max(1);
    let mut folders: BTreeMap<String, Vec<serde_json::Value>> = BTreeMap::new();

    for (index, (normalized, disk_path)) in scanned.iter().enumerate() {
        let _ = sink.add(IndexActionState {
            progress: index as f64 / total as f64,
            message: String::from("正在更新 ") + &disk_path.to_string_lossy(),
        });
        let value = if changed.contains(normalized.as_str()) {
            Audio::read_from_path(disk_path).map(|audio| {
                let mut value = audio.to_json_value();
                if let Ok(fingerprint) = FileFingerprint::from_path(disk_path) {
                    value["size"] = serde_json::json!(fingerprint.size.unwrap_or(0));
                }
                value
            })
        } else {
            existing
                .get(normalized)
                .cloned()
                .map(|record| with_current_size(record, disk_path))
        }
        .or_else(|| existing.get(normalized).cloned());

        if let Some(value) = value {
            if let Some(parent) = disk_path.parent() {
                let parent_path = normalize_index_path(parent)?;
                folders.entry(parent_path).or_default().push(value);
            }
        }
    }

    let folders_json: Vec<serde_json::Value> = folders
        .into_iter()
        .map(|(path, audios)| {
            let metadata = fs::metadata(&path).ok();
            let modified = metadata
                .as_ref()
                .and_then(|metadata| metadata.modified().ok())
                .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                .unwrap_or(Duration::ZERO)
                .as_secs();
            let latest = audios
                .iter()
                .filter_map(|audio| audio["created"].as_u64())
                .max()
                .unwrap_or(0);
            serde_json::json!({
                "path": path,
                "modified": modified,
                "latest": latest,
                "audios": audios,
            })
        })
        .collect();
    let normalized_roots: Vec<String> = roots
        .iter()
        .filter_map(|root| normalize_index_path(root).ok())
        .collect();
    let _ = sink.add(IndexActionState {
        progress: 1.0,
        message: String::new(),
    });
    Ok(serde_json::json!({
        "version": 110,
        "roots": normalized_roots,
        "folders": folders_json,
    }))
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

/// for Flutter
/// 读取既有索引，递归扫描配置目录，并仅重新读取新增或变更文件的标签。
pub fn update_index(index_path: String, sink: StreamSink<IndexActionState>) -> anyhow::Result<()> {
    let index_path = PathBuf::from(index_path).join("index.json");
    let bytes = fs::read(&index_path)?;
    let existing_index: serde_json::Value = serde_json::from_slice(&bytes)?;
    if !existing_index.is_object() && !existing_index.is_array() {
        return Err(anyhow::anyhow!("invalid index JSON"));
    }
    let roots = configured_roots_from_index(&existing_index)?;
    let updated_index = build_incremental_index(&roots, &existing_index, &sink)?;
    write_index_atomically(&index_path, &updated_index)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifies_recursive_path_changes() {
        let root = std::env::temp_dir().join(format!(
            "coriander-tag-reader-{}",
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let nested = root.join("nested");
        fs::create_dir_all(&nested).unwrap();
        let unchanged = root.join("unchanged.mp3");
        let modified = nested.join("modified.mp3");
        let added = nested.join("added.mp3");
        fs::write(&unchanged, b"same").unwrap();
        fs::write(&modified, b"old").unwrap();

        let mut existing = std::collections::HashMap::new();
        existing.insert(
            normalize_index_path(&unchanged).unwrap(),
            FileFingerprint::from_path(&unchanged).unwrap(),
        );
        existing.insert(
            normalize_index_path(&modified).unwrap(),
            FileFingerprint::from_path(&modified).unwrap(),
        );
        existing.insert(
            normalize_index_path(&root.join("removed.mp3")).unwrap(),
            FileFingerprint {
                modified: 1,
                size: Some(1),
            },
        );

        fs::write(&modified, b"changed-size").unwrap();
        fs::write(&added, b"new").unwrap();
        let scanned = scan_audio_paths(&[root.clone()]).unwrap();
        let changes = classify_path_changes(&scanned, &existing);

        assert_eq!(changes.added.len(), 1);
        assert_eq!(changes.modified.len(), 1);
        assert_eq!(changes.removed.len(), 1);
        assert!(changes.unchanged.contains(&normalize_index_path(&unchanged).unwrap()));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_legacy_indexes_without_configured_roots() {
        let legacy = serde_json::json!({
            "version": 110,
            "folders": [{"path": "D:/Music/ArtistA/Album1", "audios": []}],
        });

        let error = configured_roots_from_index(&legacy).unwrap_err();

        assert!(error.to_string().contains("rebuild the library"));
    }

    #[test]
    fn rejects_an_unreadable_configured_scan_root() {
        let missing = std::env::temp_dir().join(format!(
            "coriander-missing-root-{}",
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));

        assert!(scan_audio_paths(&[missing]).is_err());
    }

    #[test]
    fn legacy_fingerprint_without_size_keeps_unchanged_paths() {
        let root = std::env::temp_dir().join(format!(
            "coriander-legacy-fingerprint-{}",
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let unchanged = root.join("unchanged.mp3");
        let changed = root.join("changed.mp3");
        fs::write(&unchanged, b"same").unwrap();
        fs::write(&changed, b"old").unwrap();
        let mut records = HashMap::new();
        for path in [&unchanged, &changed] {
            let normalized = normalize_index_path(path).unwrap();
            let modified = FileFingerprint::from_path(path).unwrap().modified;
            records.insert(normalized, serde_json::json!({"modified": modified}));
        }
        fs::write(&changed, b"changed-size").unwrap();

        let scanned = scan_audio_paths(&[root.clone()]).unwrap();
        let changes = classify_path_changes(&scanned, &existing_fingerprints(&records));

        assert_eq!(changes.unchanged, [normalize_index_path(&unchanged).unwrap()]);
        assert_eq!(changes.modified, [normalize_index_path(&changed).unwrap()]);
        fs::remove_dir_all(root).unwrap();
    }
}
