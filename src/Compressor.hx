package;

import sys.io.Process;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Bytes;
import haxe.io.Path;
#if hxp
import hxp.System;
#end
#if neko
import neko.vm.Gc;
#end

using StringTools;

import lime.graphics.Image;

class Compressor
{
  static var CACHE_DIR:String;
  static var astcFile:String = null;
  static var version:String = "0.0.1";
  static var qualityOptions:Array<String> = ['-fastest', '-fast', '-medium', '-thorough', '-exhaustive'];

  public static function main()
  {
    CACHE_DIR = Sys.getEnv("TEMP");
    var args = Sys.args().copy();

    #if hxp
    switch (System.hostPlatform)
    {
      case WINDOWS:
        astcFile = "astcenc-win.exe";
        CACHE_DIR = Sys.getEnv("TEMP");
      case MAC:
        astcFile = "./astcenc-mac";
        CACHE_DIR = Sys.getEnv("TMPDIR")
      default:
        Sys.println('[Error] Unsupported platform!');
    }
    #end

    if (astcFile == null)
    {
      return;
    }

    if (args.length <= 1 || (args.contains("-help") || args.contains("--help")))
    {
      Sys.println('===========================================');
      Sys.println(' ASTC Compressor v$version');
      Sys.println('===========================================');
      Sys.println('');
      Sys.println('Usage:');
      Sys.println('  haxelib run astc-compressor <path> <block-size> <quality> [-premultiply]');
      Sys.println('');
      Sys.println('Arguments:');
      Sys.println('  <path>         Path to a PNG file or a folder containing PNG images.');
      Sys.println('  <block-size>   Block size for ASTC compression (e.g., 4x4, 5x5, 8x8).');
      Sys.println('                 Smaller block sizes = better quality, bigger files.');
      Sys.println('  <quality>      Compression quality setting:');
      Sys.println('                   -fastest    (lowest quality, fastest encoding)');
      Sys.println('                   -fast       (faster encoding)');
      Sys.println('                   -medium     (default, balanced)');
      Sys.println('                   -thorough   (higher quality, slower)');
      Sys.println('                   -exhaustive (highest quality, very slow)');
      Sys.println('  -premultiply   (Optional) Premultiply alpha before compressing.');
      Sys.println('');
      Sys.println('Examples:');
      Sys.println('  haxelib run astc-compressor ./textures 4x4 -medium');
      Sys.println('  haxelib run astc-compressor ./image.png 8x8 -thorough -premultiply');
      Sys.println('');
      Sys.println('Notes:');
      Sys.println('  - Premultiplied alpha is useful for correct blending in some engines.');
      Sys.println('  - Always prefer 4x4 block size for highest visual quality.');
      Sys.println('');

      return;
    }

    final path = args[0];
    final blockSize = args[1];
    final quality = args[2];
    final premultiply = args[3] == "-premultiply";

    var errored = false;

    if (!FileSystem.exists(path))
    {
      Sys.println('[Error] Invalid path: ' + path);
      errored = true;
    }

    var blockParts = blockSize.split('x');
    if (blockParts.length != 2 || !~/^\d+$/.match(blockParts[0]) || !~/^\d+$/.match(blockParts[1]))
    {
      Sys.println('[Error] Invalid block size: ' + blockSize + ' (expected formats: 4x4, 6x6, 8x8)');
      errored = true;
    }

    if (!qualityOptions.contains(quality))
    {
      Sys.println('[Error] Invalid quality option: ' + quality);
      Sys.println('[NOTE] Available Quality Options: ${qualityOptions.join(', ')}');
      errored = true;
    }

    if (errored)
    {
      Sys.println('');
      Sys.println('Use: haxelib run astc-compressor --help');
      return;
    }

    if (!path.endsWith(".png"))
    {
      compressDirectory(path, quality, blockSize, premultiply);
    }
    else
    {
      compressImage(path, quality, blockSize, premultiply);
    }
  }

  static function compressDirectory(path:String, quality:String, blockSize:String, premultiply:Bool)
  {
    for (entry in FileSystem.readDirectory(path))
    {
      if (isDirectory(Path.join([path, entry])))
      {
        compressDirectory(Path.join([path, entry]), quality, blockSize, premultiply);
      }
      else
      {
        if (entry.endsWith('.png'))
          compressImage(Path.join([path, entry]), quality, blockSize, premultiply);
      }
    }
  }

  static function compressImage(path:String, quality:String, blockSize:String, premultiply:Bool)
  {
    final outputPath = Path.withoutExtension(path) + ".astc";
    final inputPath = premultiply ? Path.join([CACHE_DIR, "astc-compressor", Path.withoutExtension(Path.withoutDirectory(path)) + "-premultiplied." + Path.extension(path)]) : path;

    if (premultiply)
    {
      var image = Image.fromFile(path);
      image.premultiplied = true;

      final bytes = image.encode();
      FileSystem.createDirectory(Path.directory(inputPath));
      File.saveBytes(inputPath, bytes);

    	image.data = null;
			image = null;
      Gc.run(false);
    }

    var proc = new Process(astcFile, ["-cl", inputPath, outputPath, blockSize, quality]);
    proc.close();

    Gc.run(true);

    Sys.println('[✔] ' + (premultiply ? 'Premultiplied and ' : '') + 'compressed "$path" as ASTC ($blockSize, $quality)');
  }

  // Neko's FileSystem.isDirectory is dead so we do smth funny
  static function isDirectory(path:String):Bool
  {
    try
    {
      FileSystem.readDirectory(path);
      return true;
    }
    catch(e)
    {
      return false;
    }
  }
}
