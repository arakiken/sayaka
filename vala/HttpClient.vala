/*
 * Copyright (C) 2015 Y.Sugahara (moveccr)
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

namespace ULib
{
	public class HttpClient
	{
		private Diag diag = new Diag("HttpClient");

		// ソケット
		public SocketClient Sock;

		// 基本コネクション。
		public SocketConnection BaseConn;

		// https の時の TlsConnection。
		public TlsClientConnection Tls;

		// 最終的に選択されたコネクション。
		// uri.Scheme に応じて設定される。
		public weak IOStream Conn;

		// パース後の URI
		public ParsedUri Uri;

		// リクエスト時にサーバへ送る追加のヘッダ
		// Host: はこちらで生成するので呼び出し側が指定しないでください。
		public Dictionary<string, string> SendHeaders;

		// 受け取ったヘッダ
		public Array<string> RecvHeaders;

		// 受け取った応答行
		public string ResultLine;

		// 受け取った応答コード
		public int ResultCode;

		// コネクションに使用するプロトコルファミリ
		// IPv4/IPv6 only にしたい場合はコンストラクタ後に指定?
		public SocketFamily Family;

		// 特定サーバだけの透過プロキシモード?
		// "userstream.twitter.com=http://127.0.0.1:10080/"
		// みたいに指定する
		public static string ProxyMap;


		// uri をターゲットにした HttpClient を作成します。
		public HttpClient(string uri)
		{
 			diag = new Diag("HttpClient");

			// XXX AF_UNSPEC がなさげなのでとりあえず代用
			Family = SocketFamily.INVALID;

			Uri = ParsedUri.Parse(uri);
			diag.Debug(Uri.to_string());

			SendHeaders = new Dictionary<string, string>();
			RecvHeaders = new Array<string>();
		}

		// uri から GET して、ストリームを返します。
		public DataInputStream GET() throws Error
		{
			diag.Trace("GET()");
			DataInputStream dIn = null;

			while (true) {

				Connect();

				SendRequest("GET");

				dIn = new DataInputStream(Conn.input_stream);
				dIn.set_newline_type(DataStreamNewlineType.CR_LF);

				ReceiveHeader(dIn);

				if (300 <= ResultCode && ResultCode < 400) {
					Close();
					var location = GetHeader(RecvHeaders, "Location");
					diag.Debug(@"Redirect to $(location)");
					if (location != null) {
						Uri = ParsedUri.Parse(location);
						diag.Debug(Uri.to_string());
						continue;
					}
				}

				break;
			}

			DataInputStream rv;
			var transfer_encoding = GetHeader(RecvHeaders, "Transfer-Encoding");
			if (transfer_encoding == "chunked") {
				// チャンク
				diag.Debug("use ChunkedInputStream");
				rv = new ChunkedInputStream(dIn);
			} else {
				// ボディをメモリに読み込んで、そのメモリへのストリームを返す。
				// https の時はストリームの終了で TlsConnection が例外を吐く。
				// そのため、ストリームを直接外部に渡すと、予期しないタイミング
				// で例外になるので、一旦メモリに読み込む。
				diag.Debug("use MemoryInputStream");
				var ms = new MemoryOutputStream.resizable();
				try {
					ms.splice(dIn, 0);
				} catch {
					// ignore
				}
				ms.close();

				// TODO: ソケットのクローズ

				// ms のバックエンドバッファの所有権を移す。
				var msdata = ms.steal_data();
				msdata.length = (int)ms.get_data_size();
				var msin = new MemoryInputStream.from_data(msdata, null);
				return new DataInputStream(msin);
			}

			return rv;
		}

		// リクエストを発行します。
		private void SendRequest(string verb) throws Error
		{
			var sb = new StringBuilder();

			sb.append(@"$(verb) $(Uri.PQF()) HTTP/1.1\r\n");

			SendHeaders.AddIfMissing("connection", "close");

			foreach (KeyValuePair<string, string> h in SendHeaders) {
				sb.append(@"$(h.Key): $(h.Value)\r\n");
			}
			sb.append("Host: %s\r\n".printf(Uri.Host));
			sb.append("\r\n");

			diag.Debug(@"Request $(verb)\n$(sb.str)");

			var msg = sb.str;

			Conn.output_stream.write(msg.data);
			diag.Trace("SendRequest() request sent");
		}

		// ヘッダを受信します。
		private void ReceiveHeader(DataInputStream dIn) throws Error
		{
			RecvHeaders = null;
			RecvHeaders = new Array<string>();

			diag.Trace("ReceiveHeader()");

			// 1行目は応答行
			ResultLine  = dIn.read_line();
			if (ResultLine == null || ResultLine == "") {
				throw new IOError.CONNECTION_CLOSED("");
			}
			diag.Debug(@"HEADER $(ResultLine)");

			var proto_arg = StringUtil.Split2(ResultLine, " ");
			if (proto_arg[0] == "HTTP/1.1" || proto_arg[0] == "HTTP/1.0") {
				var code_msg = StringUtil.Split2(proto_arg[1], " ");
				ResultCode = int.parse(code_msg[0]);
				diag.Debug(@"ResultCode=$(ResultCode)");
			}

			// 2行目以降のヘッダを読みこむ
			// 1000 行で諦める
			for (int i = 0; i < 1000; i++) {

				var s = dIn.read_line();
				if (s == null) {
					throw new IOError.CONNECTION_CLOSED("");
				}

				diag.Debug(@"HEADER |$(s)|");

				// End of header
				if (s == "") break;

				// ヘッダ行
				if (s[0] == ' ') {
					// 行継続
					var lastidx = RecvHeaders.length - 1;
					var prev = RecvHeaders.index(lastidx);
					RecvHeaders.remove_index(lastidx);
					prev += s.chomp();
					RecvHeaders.append_val(prev);
				} else {
					RecvHeaders.append_val(s.chomp());
				}
			}

			// XXX: 1000 行あったらどうすんの
		}

		// ヘッダ配列から指定のヘッダを検索してボディを返します。
		private string GetHeader(Array<string> header, string key)
		{
			var key2 = key.ascii_down();
			for (var i = 0; i < header.length; i++) {
				var kv = StringUtil.Split2(header.index(i), ":");
				if (key2 == kv[0].ascii_down()) {
					return kv[1].chug();
				}
			}
			return "";
		}

		// uri へ接続します。
		private void Connect() throws Error
		{
			int16 port = 80;

			// デフォルトポートの書き換え
			if (Uri.Scheme == "https") {
				port = 443;
			}

			if (Uri.Port != "") {
				port = (int16)int.parse(Uri.Port);
			}

			// 透過プロキシ(?)設定があれば対応。
			var proxyTarget = "";
			ParsedUri proxyUri = new ParsedUri();
			if (ProxyMap != null && ProxyMap != "") {
				var map = ProxyMap.split("=");
				proxyTarget = map[0];
				proxyUri = ParsedUri.Parse(map[1]);
			}

			// 名前解決
			List<InetAddress> addressList;
			if (Uri.Host == proxyTarget) {
				// プロキシサーバのアドレスを設定
				diag.Debug(@"Use ProxyMap: $(Uri.Host) -> $(proxyUri)\n");
				addressList = new List<InetAddress>();
				addressList.append(new InetAddress.from_string(proxyUri.Host));
				port = (int16)int.parse(proxyUri.Port);
				// アドレスファミリ指定を無効にする。
				// そもそもこれは名前を解決した時用のオプションであって、
				// ここではプロキシ指定したアドレスを優先してほしいはず。
				Family = SocketFamily.INVALID;
			} else {
				// 普通に名前解決
				var resolver = Resolver.get_default();
				addressList = resolver.lookup_by_name(Uri.Host, null);
			}

			InetAddress address = null;
			for (var i = 0; i < addressList.length(); i++) {
				address = addressList.nth_data(i);
				diag.Debug(@"Connect(): try [$(i)]=$(address) port=$(port)");

				// アドレスファミリのチェック
				if (Family != SocketFamily.INVALID) {
					if (address.get_family() != Family) {
						diag.Debug(@"Connect: $(address) is not $(Family),"
							+ " skip");
						continue;
					}
				}

				// 基本コネクションの接続
				Sock = new SocketClient();
				try {
					BaseConn = Sock.connect(
						new InetSocketAddress(address, port));
				} catch (Error e) {
					diag.Debug(@"Sock.connect: $(e.message)");
					continue;
				}

				var scheme = proxyUri.Scheme != ""
					? proxyUri.Scheme : Uri.Scheme;
				if (scheme == "https") {
					// TLS コネクションに移行する。
					diag.Trace("Connect(): TlsClientConnecton.new");
					Tls = TlsClientConnection.@new(BaseConn, null);

					// どんな証明書でも受け入れる。
					// 本当は、Tls.validation_flags で制御できるはずだが
					// うまくいかない。
					// accept_certificate signal (C# の event 相当)
					// を接続して対処したらうまく行った。
					Tls.accept_certificate.connect(Tls_Accept);
					Conn = Tls;
				} else {
					Conn = BaseConn;
				}
				// つながったら OK なのでループ抜ける。
				break;
			}

			if (Conn == null) {
				throw new IOError.HOST_NOT_FOUND(@"$(Uri.Host)");
			}
		}

		// TLS の証明書を受け取った時のイベント。
		private bool Tls_Accept(TlsCertificate peer_cert,
			TlsCertificateFlags errors)
		{
			diag.Trace("Tls_Accept");
			// true を返すと、その証明書を受け入れる。
			// がばがば
			return true;
		}

		// 接続を閉じます。
		public void Close() throws Error
		{
			diag.Trace("Close");
			Conn = null;
			if (Tls != null) {
				Tls.close();
				Tls = null;
			}
			if (BaseConn != null) {
				BaseConn.close();
				BaseConn = null;
			}
			if (Sock != null) {
				Sock = null;
			}
		}
	}

	public class ChunkedInputStream
		: DataInputStream
	{
		private Diag diag = new Diag("ChunkedInputStream");

		// 入力ストリーム
		private DataInputStream Src;

		private MemoryInputStream Chunks;

		public ChunkedInputStream(DataInputStream stream)
		{
			Src = stream;
			Src.set_newline_type(DataStreamNewlineType.CR_LF);

			Chunks = new MemoryInputStream();
		}

		public override bool close(Cancellable? cancellable = null)
			throws IOError
		{
			// XXX Not implemented
			return false;
		}

		public override ssize_t read(uint8[] buffer,
			Cancellable? cancellable = null) throws IOError
		{
			diag.Debug("read %d".printf(buffer.length));

			// 内部バッファの長さ
			int64 chunksLength;
			try {
				Chunks.seek(0, SeekType.END);
				chunksLength = Chunks.tell();
			} catch (Error e) {
				diag.Debug(@"seek(END) failed: $(e.message)");
				chunksLength = 0;
			}
			diag.Debug(@"chunksLength=$(chunksLength)");

			while (chunksLength == 0) {
				// 内部バッファが空なら、チャンクを読み込み
				var intlen = 0;
				var len = Src.read_line();
				if (len == null) {
					// EOF
					diag.Debug("Src is EOF");
					return -1;
				}
				len.scanf("%x", &intlen);
				diag.Debug(@"intlen = $(intlen)");
				if (intlen == 0) {
					// データ終わり。CRLF を読み捨てる
					Src.read_line();
					break;
				}

				uint8[] buf = new uint8[intlen];
				size_t redlen;
				bool r = Src.read_all(buf, out redlen);
				if (r == false) {
					diag.Debug("read_all false");
					return -1;
				}
				diag.Debug(@"redlen=$(redlen)");
				if (redlen != intlen) {
					diag.Debug(@"redlen=$(redlen) intlen=$(intlen)");
					return -1;
				}

				Chunks.add_data(buf, null);
				// 長さを再計算
				try {
					Chunks.seek(0, SeekType.END);
				} catch (Error e) {
					diag.Debug(@"seek(END) failed: $(e.message)");
				}
				chunksLength = Chunks.tell();
				diag.Debug(@"chunksLength=$(chunksLength)");

				// 最後の CRLF を読み捨てる
				Src.read_line();
			}

			// buffer に入るだけコピー
			var copylen = chunksLength;
			if (copylen > buffer.length) {
				copylen = buffer.length;
			}
			diag.Debug(@"copylen=$(copylen)");
			try {
				Chunks.seek(0, SeekType.SET);
			} catch (Error e) {
				diag.Debug(@"seek(SET) failed: $(e.message)");
			}
			Chunks.read(buffer);

			var remain = chunksLength - copylen;
			diag.Debug(@"remain=$(remain)");
			if (remain > 0) {
				// 読み込み終わった部分を Chunks を作りなおすことで破棄する
				uint8[] tmp = new uint8[remain];
				try {
					Chunks.seek(copylen, SeekType.SET);
				} catch (Error e) {
					diag.Debug(@"seek(SET) failed: $(e.message)");
				}
				Chunks.read(tmp);
				Chunks = null;
				Chunks = new MemoryInputStream();
				Chunks.add_data(tmp, null);
				chunksLength = Chunks.tell();
				diag.Debug(@"new ChunkLength=$(chunksLength)");
			} else {
				// きっかりだったので空にする。
				Chunks = null;
				Chunks = new MemoryInputStream();
			}

			return (ssize_t)copylen;
		}
	}
}
