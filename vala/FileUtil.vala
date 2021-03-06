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
	// .Net File.ReadAllText 相当品です。
	// エンコーディングはサポートしていません。
	public static string FileReadAllText(string filename) throws Error
	{
		var sb = new StringBuilder();

		var f = File.new_for_path(filename);
		var stream = new DataInputStream(f.read());
		string buf;
		while ((buf = stream.read_line()) != null) {
			sb.append(buf);
		}

		return sb.str;
	}

	// .Net File.WriteAllText 相当品です。
	public static void FileWriteAllText(string filename, string text)
		throws Error
	{
		var f = File.new_for_path(filename);
		var outputstream = f.replace(null, false, FileCreateFlags.PRIVATE);
		var stream = new DataOutputStream(outputstream);
		stream.put_string(text);
	}

}

// GLib.FileStream を gio の GLib.InputStream にラップするクラス
// stdin をラップするために作った。
public class InputStreamFromFileStream
	: InputStream
{
	private unowned FileStream? target;

	public InputStreamFromFileStream(FileStream fs)
	{
		target = fs;
	}

	public override bool close(Cancellable? cancellable = null) throws IOError
	{
		target = null;
		return true;
	}

	public override ssize_t read(uint8[] buffer, Cancellable? cancellable = null) throws IOError
	{
		return (ssize_t)target.read(buffer, 1);
	}
}

public class OutputStreamFromFileStream
	: OutputStream
{
	private unowned FileStream? target;

	public OutputStreamFromFileStream(FileStream fs)
	{
		target = fs;
	}

	public override bool close(Cancellable? cancellable = null) throws IOError
	{
		target = null;
		return true;
	}

	public override ssize_t write(uint8[] buffer, Cancellable? cancellable = null) throws IOError
	{
		return (ssize_t)target.write(buffer, 1);
	}
}

