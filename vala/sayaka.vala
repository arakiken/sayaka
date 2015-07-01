using System.OS;
using System.Collections.Generic;

class Program
{
	public static int main(string[] args)
	{
#if !false
		var sayaka = new SayakaMain();
		return sayaka.Main(args);
#else
		var sx = new SixelConverter();
	//	sx.Load("x68k.bmp");
		sx.Load("IMG_0284.JPG");
//		sx.Load("snake.jpg");

#if false
		sx.SetPaletteFixed16();
		sx.ReduceFixed16();
		sx.SimpleReduceFixed16();
#endif
#if !false
		sx.SetPaletteFixed8();
		sx.ReduceFixed8();
		sx.SimpleReduceFixed8();
#endif
#if false
		sx.SetPaletteFixed256();
		sx.ReduceFixed256();
		sx.SimpleReduceFixed256();
#endif

		sx.SixelToStream(stdout);
		return 0;
#endif
	}
}

// PHP 由来
class PHP
{
	public static string unescape(string text)
	{
		// PHP の htmlspecialchars_decode(ENT_NOQUOTES) 相当品
		return text
			.replace("&lt;", "<")
			.replace("&gt;", ">")
			.replace("&amp;", "&");
	}

	public static string strip_tags(string text)
	{
		StringBuilder sb = new StringBuilder();
		bool intag = false;
		for (var i = 0; i < text.length; i++) {
			var c = text[i];
			if (intag) {
				if (c == '>') {
					intag = false;
				}
			} else {
				if (c == '<') {
					intag = true;
				} else {
					sb.append_c(c);
				}
			}
		}
		return sb.str;
	}
}

class SayakaMain
{
	public const char ESC = '\x1b';
	public const string CSI = "\x1b[";

	public enum Color {
		Username,
		UserId,
		Time,
		Source,

		Retweet,
		Favorite,
		Url,
		Tag,
		Verified,
		Protected,
		NG,
		Max,
	}

	public string img2sixel;
	public int color_mode = 256;
	public bool protect;
	public bool debug;
	public int screen_cols;
	public int fontheight;
	public int iconsize;
	public int imagesize;
	public int global_indent_level;
	public bool bg_white;
	public string[] color2esc = new string[Color.Max];

	public string cachedir = "./cache";

	static SayakaMain sayakaMain;

	public SayakaMain()
	{
		sayakaMain = this;
	}

	public int Main(string[] args)
	{
		for (var i = 1; i < args.length; i++) {
			switch (args[i]) {
			 case "--color":
				color_mode = int.parse(args[++i]);
				break;
			 case "--noimg":
				img2sixel = "none";
				break;
			 case "--white":
				bg_white = true;
				break;
			 case "--debug":
				debug = true;
				break;
			 default:
				usage();
				break;
			}
		}

		init_stream();

		string line;
		while ((line = stdin.read_line()) != null) {
			var parser = new ULib.JsonParser();
			try {
				var obj = parser.Parse(line);
				TRACE("obj=%p".printf(obj));
				TRACE("obj=%s\n".printf(obj.ToString()));
				showstatus_callback(obj);
			} catch {
				stdout.printf("error\n");
				return 0;
			}
		}
		return 0;
	}

	// ユーザストリームモードのための準備
	public void init_stream()
	{
		// 色の初期化
		init_color();

		// img2sixel
		// --noimg オプションなら img2sixel を使わない
		// そうでなければ探して使う。がなければ使わない
		if (img2sixel == "none") {
			img2sixel = "";
		} else {
			string output;
			try {
				Process.spawn_command_line_sync("which img2sixel",
					out output);
			} catch {
			}
			img2sixel = TrimEnd(output);
		}
		if (img2sixel != "") {
			img2sixel += " -S";
			if (color_mode == 2) {
				img2sixel += " -e --quality=low";
			} else if (color_mode <= 16) {
				img2sixel += " -m colormap%d.png".printf(color_mode);
			}
		}

		// シグナルハンドラを設定
		Posix.@signal(SIGWINCH, signal_handler);

		// 一度手動で呼び出して桁数を取得
		signal_handler(SIGWINCH);
	}

	// 1ツイートを表示するコールバック関数
	// ここではループ中からそのまま呼ばれる
	public void showstatus_callback(ULib.Json obj)
	{
		ULib.Json status = null;

		// obj が元オブジェクト (イベント or メッセージ)

		// 録画

		if (obj.Has("event")) {
			// event => イベント種別
			//			"favorite", "unfavorite", "follow", "unfollow", ...
			// timestamp_ms => イベント発生時刻(UNIXTIME)
			// created_at => イベント発生時刻

			var event = obj.GetString("event");
			switch (event) {
			 case "favorite":
				if (obj.Has("target_object")) {
					status = obj.GetJson("target_object");

					// これだけだと、$status から $object が拾えないので
					// $object をバックリンクしておく。
					status.AsObject.AddOrUpdate("object", obj);
				}
				break;
			 case "follow":
			 case "mute":
			 case "unmute":
			 default:
				return;
			}
		} else if (obj.Has("text")) {
			// 通常のツイート
			// status はツイートメッセージ
			status = obj;
		} else if (obj.Has("friends")) {
			// 最初に送られてくる friends リストはいらない
			return;
		} else {
			// それ以外の情報はとりあえず無視
			return;
		}

		// ミュート...

		// NGワード...

		showstatus(status);
		stdout.printf("\n");
	}

	// 1ツイートを表示
	public void showstatus(ULib.Json status)
	{
		ULib.Json obj = status.GetJson("object");

		// RT なら、RT 元を $status、RT先を $s
		ULib.Json s = status;
		if (status.Has("retweeted_status")) {
			s = status.GetJson("retweeted_status");
		}

		var s_user = s.GetJson("user");
		var userid = coloring(formatid(
			s_user.GetString("screen_name")),
			Color.UserId);
		var name = coloring(formatname(
			s_user.GetString("name")),
			Color.Username);
		var src = coloring(PHP.unescape(PHP.strip_tags(
			s.GetString("source") + "から")),
			Color.Source);
		var time = coloring(formattime(s), Color.Time);
		var verified = s_user.GetBool("verified")
			? coloring(" ●", Color.Verified)
			: "";
		var protected = s_user.GetBool("protected")
			? coloring(" ■", Color.Protected)
			: "";

		// --protect オプションなら鍵ユーザのツイートを表示しない
		if (protect == true && protected != "") {
			print_(coloring("鍵垢", Color.NG) + "\n"
				+ time);
			stdout.printf("\n");
			return;
		}

		var mediainfo = new Array<Dictionary<string, string>>();
		var msg = formatmsg(s, ref mediainfo);

		// 今のところローカルアカウントはない
		var profile_image_url = s_user.GetString("profile_image_url");

		show_icon(PHP.unescape(s_user.GetString("screen_name")),
			profile_image_url);
		stdout.printf("\r");
		stdout.printf(CSI + "3A");

		print_(name + " " + userid + verified + protected);
		stdout.printf("\n");
		print_(msg);
		stdout.printf("\n");

		// picture
#if false
		foreach (var m in mediainfo) {
			stdout.printf(CSI + "6C");
			show_photo();
			stdout.printf("\r");
		}
#endif

		// コメント付きRT の引用部分
		if (s.Has("quoted_status")) {
			// この中はインデントを一つ下げる
			stdout.printf("\n");
			global_indent_level++;
			showstatus(s.GetJson("quoted_status"));
			global_indent_level--;
		}

		// このステータスの既 RT、既ふぁぼ数
		var rtmsg = "";
		var favmsg = "";
		// RT
		var rtcnt = s.GetInt("retweet_count");
		if (rtcnt > 0) {
			rtmsg = coloring(" %dRT".printf(rtcnt), Color.Retweet);
		}
		// Fav
		var favcnt = s.GetInt("favorite_count");
		if (favcnt > 0) {
			favmsg = coloring(" %dFav".printf(favcnt), Color.Favorite);
		}
		print_("%s %s%s%s".printf(time, src, rtmsg, favmsg));
		stdout.printf("\n");

		// リツイート元
		if (status.Has("retweeted_status")) {
			var user = status.GetJson("user");
			var rt_time   = formattime(status);
			var rt_userid = formatid(user.GetString("screen_name"));
			var rt_name   = formatname(user.GetString("name"));
			print_(coloring(@"$rt_time $rt_name $rt_userid がリツイート",
				Color.Retweet));
			stdout.printf("\n");
		}

		// ふぁぼ元
		if (obj != null && obj.GetString("event") == "favorite") {
			var user = obj.GetJson("source");
			var fav_time   = formattime(obj);
			var fav_userid = formatid(user.GetString("screen_name"));
			var fav_name   = formatname(user.GetString("name"));
			print_(coloring(@"$fav_time $fav_name $fav_userid がふぁぼ",
				Color.Favorite));
			stdout.printf("\n");
		}
	}

	public void print_(string msg)
	{
		string rv;
		rv = make_indent(msg);

		// XXX 置換

		// XXX 文字コード

		stdout.printf("%s", rv);
	}

	// インデントをつける
	public string make_indent(string text)
	{
		// 桁数が分からない場合は何もしない
		if (screen_cols < 1) {
			return text;
		}

		// インデント階層
		var left = 6 * (global_indent_level + 1);
		string indent = CSI + @"$(left)C";

		bool inescape = false;
		StringBuilder newtext = new StringBuilder();
		newtext.append(indent);
		var x = left;
		unichar uni;
		for (var i = 0; text.get_next_char(ref i, out uni); ) {
			if (inescape) {
				newtext.append_unichar(uni);
				if (uni == 'm') {
					inescape = false;
				}
			} else {
				if (uni == ESC) {
					newtext.append_unichar(uni);
					inescape = true;
				} else if (uni == '\n') {
					newtext.append_unichar(uni);
					newtext.append(indent);
					x = left;
				} else if (uni.iswide()) {
					if (x > screen_cols - 2) {
						newtext.append("\n");
						newtext.append(indent);
						x = left;
					}
					newtext.append_unichar(uni);
					x += 2;
				} else {
					newtext.append_unichar(uni);
					x++;
				}
				if (x > screen_cols - 1) {
					newtext.append("\n");
					newtext.append(indent);
					x = left;
				}
			}
		}
		return newtext.str;
	}

	// 名前表示用に整形
	public string formatname(string text)
	{
		return PHP.unescape(text);	/* XXX */
	}

	// ID 表示用に整形
	public string formatid(string text)
	{
		return "@" + PHP.unescape(text);
	}

	// 色定数
	public const string BOLD		= "1";
	public const string UNDERSCORE	= "4";
	public const string STRIKE		= "9";
	public const string BLACK		= "30";
	public const string RED			= "31";
	public const string GREEN		= "32";
	public const string BROWN		= "33";
	public const string BLUE		= "34";
	public const string MAGENTA		= "35";
	public const string CYAN		= "36";
	public const string WHITE		= "37";
	public const string GRAY		= "90";
	public const string YELLOW		= "93";

	public void init_color()
	{
		string blue;
		string green;
		string username;
		string fav;

		// 黒背景か白背景かで色合いを変えたほうが読みやすい
		if (bg_white) {
			blue = BLUE;
		} else {
			blue = CYAN;
		}

		// ユーザ名。白地の場合は出来ればもう少し暗めにしたい
		if (bg_white && color_mode > 16) {
			username = "38;5;28";
		} else {
			username = BROWN;
		}

		// リツイートは緑色。出来れば濃い目にしたい
		if (color_mode > 16) {
			green = "38;5;28";
		} else {
			green = GREEN;
		}

		// ふぁぼは黄色。白地の場合は出来れば濃い目にしたいが
		// こちらは太字なのでユーザ名ほどオレンジにしなくてもよさげ。
		if (bg_white && color_mode > 16) {
			fav = "38;5;184";
		} else {
			fav = BROWN;
		}

		color2esc[Color.Username]	= username;
		color2esc[Color.UserId]		= blue;
		color2esc[Color.Time]		= GRAY;
		color2esc[Color.Source]		= GRAY;

		color2esc[Color.Retweet]	= @"$(BOLD);$(green)";
		color2esc[Color.Favorite]	= BOLD + ";" + fav;
		color2esc[Color.Url]		= @"$(UNDERSCORE);$(blue)";
		color2esc[Color.Tag]		= blue;
		color2esc[Color.Verified]	= CYAN;
		color2esc[Color.Protected]	= GRAY;
		color2esc[Color.NG]			= @"$(STRIKE);$(GRAY)";
	}

	public string coloring(string text, Color col)
	{
		string rv;

		if (color2esc[col] != null) {
			rv = @"$(CSI)$(color2esc[col])m$(text)$(CSI)0m";
		} else {
			rv = @"Coloring($(text),$(col))";
		}
		return rv;
	}

	// $object の日付時刻を表示用に整形して返す。
	// timestamp_ms があれば使い、なければ created_at を使う。
	// 今のところ、timestamp_ms はたぶん新しめのツイート/イベント通知には
	// 付いてるはずだが、リツイートされた側は created_at しかない模様。
	public string formattime(ULib.Json obj)
	{
		// vala の DateTime はセットする時に UTC かローカルタイムかを
		// 決めたらそれ以降変えられないようなので(?)、
		// 先に now_local() を作っといて、そのローカルタイムから
		// utc_offset を取得しておく…。嘘だと思うけど…。
		DateTime now = new DateTime.now_local();
		int utc_offset = (int)((int64)now.get_utc_offset() / 1000 / 1000);

		DateTime dt;
		if (obj.Has("timestamp_ms")) {
			// 数値のようにみえる文字列で格納されている
			var timestamp_ms = obj.GetString("timestamp_ms");
			var unixtime = int64.parse(timestamp_ms) / 1000;
			dt = new DateTime.from_unix_utc(unixtime);
		} else {
			var created_at = obj.GetString("created_at");
			dt = conv_twtime_to_datetime(created_at);
		}

		// dt は UTC で作ったらローカルタイムに出来ないっぽいので
		// ここで時差分を追加してやる? 嘘だろ…。
		dt = dt.add_hours(utc_offset / 3600);

		if (dt.format("%F") == now.format("%F")) {
			// 今日なら時刻のみ
			return dt.format("%T");
		} else {
			return dt.format("%F %T");
		}
	}

	// twitter 書式の日付時刻から DateTime を作って返す。
	// "Wed Nov 18 18:54:12 +0000 2009"
	public DateTime conv_twtime_to_datetime(string instr)
	{
		string[] w = instr.split(" ");
		string monname = w[1];
		int mday = int.parse(w[2]);
		string timestr = w[3];
		int year = int.parse(w[5]);

		var mon = "JanFebMarAprMayJunJulAugSepOctNovDec".index_of(monname);
		mon = (mon / 3) + 1;

		string[] t = timestr.split(":");
		int hour = int.parse(t[0]);
		int min  = int.parse(t[1]);
		int sec  = int.parse(t[2]);

		return new DateTime.utc(year, mon, mday, hour, min, (double)sec);
	}

	public string formatmsg(ULib.Json s,
		ref Array<Dictionary<string, string>> mediainfo)
	{
		// 本文
		var text = s.GetString("text");

		// タグ情報を展開
		// 文字位置しか指定されてないので、text に一切の変更を加える前に
		// 調べないとタグが分からないというクソ仕様…。
		if (s.Has("entities")) {
			var hashtags = s.GetJson("entities")
			                .GetArray("hashtags");
			if (hashtags.length > 0) {
				text = format_hashtags(text, hashtags);
			}
		}

		// ハッシュタグが済んでからエスケープを取り除く
		text = PHP.unescape(text);

		return text;
	}

	public string format_hashtags(string text, Array<ULib.Json> hashtags)
	{
		var tags = new int[hashtags.length * 2];

		for (var i = 0; i < hashtags.length; i++) {
			var t = hashtags.index(i);
			// t->indices[0] … 開始位置、1文字目からなら0
			// t->indices[1] … 終了位置。この1文字前まで
			var indices = t.GetArray("indices");
			tags[i * 2 + 0] = indices.index(0).AsInt;
			tags[i * 2 + 1] = indices.index(1).AsInt;
		}

		string[] splittext = utf8_split(text, tags);
		var sb = new StringBuilder();
		for (var i = 0; i < splittext.length; i++) {
			if ((i & 1) != 0) {
				sb.append(coloring(splittext[i], Color.Tag));
			} else {
				sb.append(splittext[i]);
			}
		}

		return sb.str;
	}

	public void show_icon(string user, string img_url)
	{
		string col;

		var filename = Path.get_basename(img_url);
		if (color_mode <= 16) {
			col = @"-$(color_mode)";
		} else {
			col = "";
		}
		var img_file =
			@"icon-$(iconsize)x$(iconsize)$(col)-$(user)-$(filename).sixel";

stderr.printf("img_file=%s\n", img_file);
		if (show_image(img_file, img_url, @"$(iconsize)") == false) {
			stdout.printf("\n\n\n");
		}
	}

#if false
	public bool show_photo(string img_url, string width)
	{
		// XXX regex は…
		StringBuilder sb = new StringBuilder();
		for (var i = 0; i < img_url.length; i++) {
			var c = img_url[i];
			if (c == ':' || c == '/' || c == '('
			 || c == ')' || c == '?' || c == ' ')
			{
				sb.append("_");
			} else {
				sb.append(img_url.substring(i, 1));
			}
		}
		var img_file = sb.str;

		return show_image(img_file, img_url, width);
	}
#endif

	// 画像をキャッシュして表示
	//  $img_file はキャッシュディレクトリ内でのファイル名
	//  $img_url は画像の URL
	//  $width は画像の幅。ピクセルかパーセントで指定。
	// 表示できれば真を返す。
	public bool show_image(string img_file, string img_url, string width)
	{
		// CSI."0C" は0文字でなく1文字になってしまうので、必要な時だけ。
		if (global_indent_level > 0) {
			var left = global_indent_level * 6;
			stdout.printf(@"$(CSI)$(left)C");
		}

#if !false
		// img2sixel 使わないモードならここで帰る
		if (img2sixel == "") {
			return false;
		}

		var img_file_tmp = cachedir + "/" + img_file;
		img_file = img_file_tmp;

		if (width != "") {
			var width_tmp = @"-w $(width)";
			width = width_tmp;
		}

		FileStream stream;
		stream = FileStream.open(img_file, "r");
		if (stream == null) {
			var imgconv = @"$(img2sixel) $(width)";
			Posix.system(@"(curl -Lks $(img_url) | "
				+ @"$(imgconv) > $(img_file)) 2> /dev/null");
			stream = FileStream.open(img_file, "r");
		}
		// XXX うーん…この辺
		size_t fsize = 0;
		if (stream == null || (fsize = get_filesize(stream)) == 0) {
			Posix.unlink(img_file);
			return false;
		}

		// ファイルを読んで標準出力に吐き出す
		uint8[] buf = new uint8[fsize];
		stream.read(buf);
		stdout.write(buf);
		stdout.flush();
#else

		var sx = new SixelConverter();

		var img_file_tmp = cachedir + "/" + img_file;
		img_file = img_file_tmp;

	// width 非対応　まだね。
		if (width != "") {
			var width_tmp = @"-w $(width)";
			width = width_tmp;
		}

		try {
			sx.Load(img_file);
		} catch {
stderr.puts(@"curl $(img_url)");
			Posix.system(@"(curl -Lks $(img_url) "
				+ @" > $(img_file))");
			try {
				sx.Load(img_file);
			} catch {
				return false;
			}
		}

		// XXX うーん…この辺
#if false
		size_t fsize = 0;
		if ( (fsize = get_filesize(stream)) == 0) {
			Posix.unlink(img_file);
			return false;
		}
#endif

#if false
		sx.SetPaletteFixed8();
		sx.ReduceFix8();
		sx.SimpleReduceFixed8();
#else
		sx.SetPaletteFixed256();
		sx.ReduceFixed256();
		sx.SimpleReduceFixed256();
#endif
		sx.SixelToStream(stdout);
		stdout.flush();

#endif

		return true;
	}

	public size_t get_filesize(FileStream stream)
	{
		stream.seek(0, FileSeek.END);
		var fsize = stream.tell();
		stream.rewind();
		return fsize;
	}

	// UTF-8 文字列を分割する。
	//  utf8_split("abcdef", array(1, 3, 5, 6));
	//  rv = array("a", "bc", "de", "f");
	public string[] utf8_split(string text, int[] charpos)
	{
		var array = new Array<string>();

		// 文字数で分割
		var sb = new StringBuilder();
		unichar uni;
		int cnt = 0;
		int pos = 0;
		for (var i = 0; text.get_next_char(ref i, out uni); cnt++) {
			if (cnt == charpos[pos]) {
				array.append_val(sb.str);
				sb.erase();
				pos++;
			}
			sb.append_unichar(uni);
		}
		// 最後の文字の後ろ。タグが文字列の最後にあると、
		// その後ろはループでは表現できないので、ここで処理。
		if (cnt == charpos[pos]) {
			array.append_val(sb.str);
		}

		return array.data;
	}

	public static void signal_handler(int signo)
	{
		sayakaMain.signal_handler_2(signo);
	}

	public void signal_handler_2(int signo)
	{
		switch (signo) {
		 case SIGWINCH:
			// デフォルト値
			screen_cols = 80;
			fontheight = 14;

			winsize ws = winsize();
			var r = ioctl.TIOCGWINSZ(Posix.STDOUT_FILENO, out ws);
			if (r != 0) {
				stdout.printf("TIOCGWINSZ failed.  Using default value.\n");
			} else {
				screen_cols = ws.ws_col;

				if (ws.ws_ypixel == 0) {
					stdout.printf("TIOCCGWINSZ ws_ypixel not supported. "
						+ "Using default font height.\n");
				} else {
					if (ws.ws_row != 0) {
						fontheight = ws.ws_ypixel / ws.ws_row;
					}
				}
			}

			// フォント高さからアイコンの大きさを決定
			iconsize = (int)(fontheight * 2.5);
			imagesize = (int)(fontheight * 8.5);

			if (debug) {
				stdout.printf("screen columns=%d\n", screen_cols);
				stdout.printf("font height=%d\n", fontheight);
				stdout.printf("iconsize=%d\n", iconsize);
				stdout.printf("imagesize=%d\n", imagesize);
			}
			break;
		 default:
			break;
		}
	}

	// chomp が使えない
	public static string TrimEnd(string s)
	{
		var rv = s;
		rv._chomp();
		return rv;
	}

	public void usage()
	{
		stdout.printf("usage...\n");
		Process.exit(0);
	}

	private void TRACE(string msg)
	{
		//stderr.printf("%s\n", msg);
	}
}
