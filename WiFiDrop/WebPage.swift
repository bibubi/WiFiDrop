import Foundation

/// 浏览器端网页界面（内嵌字符串，随 App 一起分发）。
enum WebPage {
    static let index = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0a84ff">
<title>局域网传输</title>
<style>
  :root { --blue:#0a84ff; --bg:#f2f2f7; --card:#ffffff; --text:#1c1c1e; --sub:#8e8e93; --line:#e5e5ea; }
  * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
  body { margin:0; background:var(--bg); color:var(--text); padding-bottom:48px;
         font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif; }
  header { position:sticky; top:0; z-index:10; background:rgba(255,255,255,0.86);
           backdrop-filter:saturate(180%) blur(18px); border-bottom:1px solid var(--line); }
  .bar { max-width:760px; margin:0 auto; padding:12px 16px; display:flex; align-items:center; gap:10px; }
  .title { font-size:17px; font-weight:600; }
  .badge { font-size:11px; color:var(--blue); background:rgba(10,132,255,0.1); padding:3px 8px; border-radius:20px; }
  main { max-width:760px; margin:0 auto; padding:16px; }
  .card { background:var(--card); border-radius:16px; overflow:hidden; }
  .toolbar { display:flex; gap:8px; flex-wrap:wrap; margin-bottom:12px; }
  .btn { appearance:none; border:none; background:var(--blue); color:#fff; font-size:14px; font-weight:500;
         padding:9px 14px; border-radius:10px; cursor:pointer; text-decoration:none;
         display:inline-flex; align-items:center; justify-content:center; }
  .btn.ghost { background:#fff; color:var(--text); border:1px solid var(--line); }
  .btn.small { font-size:12px; padding:6px 10px; border-radius:8px; }
  .btn.danger { background:#fff; color:#ff3b30; border:1px solid #ffd6d4; }
  .btn:active { opacity:.7; }
  .crumb { display:flex; align-items:center; gap:2px; flex-wrap:wrap; margin-bottom:12px; font-size:13px; }
  .crumb-item { background:none; border:none; color:var(--blue); padding:2px 4px; font-size:13px; cursor:pointer; }
  .sep { color:var(--sub); }
  .drop { border:2px dashed #c7c7cc; border-radius:16px; padding:26px 16px; text-align:center;
          color:var(--sub); font-size:14px; margin-bottom:16px; background:#fafafe; transition:all .15s; cursor:pointer; }
  .drop.active { border-color:var(--blue); background:rgba(10,132,255,0.06); color:var(--blue); }
  .item { display:flex; align-items:center; gap:12px; padding:12px 16px; border-bottom:1px solid var(--line); }
  .item:last-child { border-bottom:none; }
  .icon { width:36px; height:36px; border-radius:9px; display:flex; align-items:center; justify-content:center;
          font-size:11px; font-weight:600; color:#fff; flex:none; }
  .icon.folder { background:#ff9f0a; }
  .icon.file { background:#5e5ce6; }
  .main { min-width:0; flex:1; }
  .name { display:block; background:none; border:none; padding:0; font-size:15px; color:var(--text);
          text-align:left; word-break:break-all; font-weight:500; cursor:pointer; }
  .meta { font-size:12px; color:var(--sub); margin-top:3px; word-break:break-all; }
  .actions { display:flex; gap:6px; flex:none; }
  .empty { padding:44px 16px; text-align:center; color:var(--sub); font-size:14px; }
  .progress { display:none; margin-bottom:12px; background:#fff; border-radius:12px; padding:12px 14px; }
  .progress.visible { display:block; }
  .progress-name { font-size:12px; color:var(--sub); margin-bottom:8px; word-break:break-all; }
  .track { height:6px; border-radius:3px; background:#e5e5ea; overflow:hidden; }
  .fill { height:100%; width:0; background:var(--blue); border-radius:3px; transition:width .12s linear; }
  .footer { text-align:center; font-size:12px; color:var(--sub); padding:20px 16px 0; }
  #toast { position:fixed; left:50%; bottom:28px; transform:translateX(-50%) translateY(20px);
           background:rgba(28,28,30,0.92); color:#fff; font-size:13px; padding:10px 16px; border-radius:20px;
           opacity:0; pointer-events:none; transition:all .2s; max-width:80vw; text-align:center; }
  #toast.visible { opacity:1; transform:translateX(-50%) translateY(0); }
</style>
</head>
<body>
<header><div class="bar"><div class="title">局域网传输</div><div class="badge">WiFi</div></div></header>
<main>
  <div class="toolbar">
    <button class="btn" id="pick">上传文件</button>
    <button class="btn ghost" id="mkdir">新建文件夹</button>
    <button class="btn ghost" id="refresh">刷新</button>
    <input id="file" type="file" multiple hidden>
  </div>
  <div class="crumb" id="crumb"></div>
  <div class="drop" id="drop">把文件拖到这里，或点击选择文件</div>
  <div class="progress" id="progress">
    <div class="progress-name" id="progress-name">正在上传</div>
    <div class="track"><div class="fill" id="progress-bar"></div></div>
  </div>
  <div class="card" id="list"></div>
  <div class="footer" id="free"></div>
</main>
<div id="toast"></div>
<script>
(function () {
  'use strict';

  var state = { path: '' };
  var queue = [];
  var uploading = false;

  function $(id) { return document.getElementById(id); }

  function encodePath(path) {
    return path.split('/').filter(Boolean).map(encodeURIComponent).join('/');
  }

  function formatSize(bytes) {
    var value = Number(bytes) || 0;
    if (value <= 0) return '0 B';
    var units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value = value / 1024;
      index += 1;
    }
    return (index === 0 ? String(Math.round(value)) : value.toFixed(1)) + ' ' + units[index];
  }

  function formatTime(seconds) {
    if (!seconds) return '';
    return new Date(seconds * 1000).toLocaleString();
  }

  function showToast(message) {
    var toast = $('toast');
    toast.textContent = message;
    toast.classList.add('visible');
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(function () { toast.classList.remove('visible'); }, 2400);
  }

  async function load(path) {
    state.path = path || '';
    try {
      var response = await fetch('/api/list?path=' + encodeURIComponent(state.path), { cache: 'no-store' });
      if (!response.ok) throw new Error('HTTP ' + response.status);
      var data = await response.json();
      render(data);
    } catch (error) {
      showToast('读取目录失败：' + error.message);
    }
  }

  function render(data) {
    renderBreadcrumb(data.path || '');
    $('free').textContent = '设备可用空间 ' + formatSize(data.free);
    var list = $('list');
    list.innerHTML = '';
    var entries = data.entries || [];
    if (!entries.length) {
      var empty = document.createElement('div');
      empty.className = 'empty';
      empty.textContent = '这个文件夹还是空的，上传一些文件试试';
      list.appendChild(empty);
      return;
    }
    entries.forEach(function (item) { list.appendChild(renderRow(item)); });
  }

  function renderRow(item) {
    var row = document.createElement('div');
    row.className = 'item';

    var icon = document.createElement('div');
    icon.className = 'icon ' + (item.dir ? 'folder' : 'file');
    icon.textContent = item.dir ? '夹' : '件';

    var main = document.createElement('div');
    main.className = 'main';

    var name = document.createElement('button');
    name.className = 'name';
    name.textContent = item.name;
    name.onclick = function () {
      if (item.dir) {
        load(item.path);
      } else {
        window.location.href = '/files/' + encodePath(item.path);
      }
    };

    var meta = document.createElement('div');
    meta.className = 'meta';
    meta.textContent = item.dir ? '文件夹' : formatSize(item.size) + ' · ' + formatTime(item.mtime);

    main.appendChild(name);
    main.appendChild(meta);

    var actions = document.createElement('div');
    actions.className = 'actions';

    if (!item.dir) {
      var link = document.createElement('a');
      link.className = 'btn small';
      link.textContent = '下载';
      link.href = '/files/' + encodePath(item.path);
      link.setAttribute('download', item.name);
      actions.appendChild(link);
    }

    var removeButton = document.createElement('button');
    removeButton.className = 'btn small danger';
    removeButton.textContent = '删除';
    removeButton.onclick = function () { deleteEntry(item); };
    actions.appendChild(removeButton);

    row.appendChild(icon);
    row.appendChild(main);
    row.appendChild(actions);
    return row;
  }

  async function deleteEntry(item) {
    if (!confirm('确定删除「' + item.name + '」吗？')) return;
    try {
      var response = await fetch('/api/delete?path=' + encodeURIComponent(item.path), { method: 'POST' });
      if (!response.ok) throw new Error('HTTP ' + response.status);
      showToast('已删除');
      load(state.path);
    } catch (error) {
      showToast('删除失败：' + error.message);
    }
  }

  async function createFolder() {
    var name = prompt('请输入文件夹名称');
    if (!name) return;
    try {
      var url = '/api/mkdir?path=' + encodeURIComponent(state.path) + '&name=' + encodeURIComponent(name);
      var response = await fetch(url, { method: 'POST' });
      if (!response.ok) throw new Error('HTTP ' + response.status);
      load(state.path);
    } catch (error) {
      showToast('创建失败：' + error.message);
    }
  }

  function addFiles(fileList) {
    if (!fileList || !fileList.length) return;
    for (var i = 0; i < fileList.length; i += 1) {
      queue.push(fileList[i]);
    }
    if (!uploading) runQueue();
  }

  async function runQueue() {
    uploading = true;
    while (queue.length > 0) {
      var file = queue.shift();
      try {
        await uploadOne(file);
        showToast('已上传 ' + file.name);
      } catch (error) {
        showToast('上传失败 ' + file.name + '：' + error.message);
      }
    }
    uploading = false;
    hideProgress();
    load(state.path);
  }

  function uploadOne(file) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      var url = '/api/upload?path=' + encodeURIComponent(state.path) + '&name=' + encodeURIComponent(file.name);
      xhr.open('POST', url, true);
      xhr.setRequestHeader('Content-Type', 'application/octet-stream');
      xhr.upload.onprogress = function (event) {
        if (event.lengthComputable) showProgress(file.name, event.loaded / event.total);
      };
      xhr.onload = function () {
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve();
        } else {
          reject(new Error('服务器返回 ' + xhr.status));
        }
      };
      xhr.onerror = function () { reject(new Error('网络中断')); };
      xhr.send(file);
    });
  }

  function showProgress(name, ratio) {
    $('progress').classList.add('visible');
    $('progress-name').textContent = '正在上传 ' + name;
    $('progress-bar').style.width = Math.round(ratio * 100) + '%';
  }

  function hideProgress() {
    $('progress').classList.remove('visible');
    $('progress-bar').style.width = '0%';
  }

  function renderBreadcrumb(path) {
    var bar = $('crumb');
    bar.innerHTML = '';

    var root = document.createElement('button');
    root.className = 'crumb-item';
    root.textContent = '根目录';
    root.onclick = function () { load(''); };
    bar.appendChild(root);

    var parts = path.split('/').filter(Boolean);
    var accumulated = '';
    parts.forEach(function (part) {
      accumulated = accumulated ? accumulated + '/' + part : part;
      var separator = document.createElement('span');
      separator.className = 'sep';
      separator.textContent = '/';
      bar.appendChild(separator);

      var button = document.createElement('button');
      button.className = 'crumb-item';
      button.textContent = part;
      var target = accumulated;
      button.onclick = function () { load(target); };
      bar.appendChild(button);
    });
  }

  function bind() {
    $('pick').onclick = function () { $('file').click(); };
    $('file').onchange = function () {
      addFiles(this.files);
      this.value = '';
    };
    $('mkdir').onclick = createFolder;
    $('refresh').onclick = function () { load(state.path); };
    $('drop').onclick = function () { $('file').click(); };

    document.addEventListener('dragover', function (event) {
      event.preventDefault();
      $('drop').classList.add('active');
    });
    document.addEventListener('dragleave', function (event) {
      if (event.target === document.documentElement) $('drop').classList.remove('active');
    });
    document.addEventListener('drop', function (event) {
      event.preventDefault();
      $('drop').classList.remove('active');
      if (event.dataTransfer) addFiles(event.dataTransfer.files);
    });
  }

  bind();
  load('');
})();
</script>
</body>
</html>
"""
}
