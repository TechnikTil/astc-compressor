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
  static var COMMAND_CWD:String;
  static var astcFile:String = null;
  static var clean:Bool = false;
  static var excludes:Array<String> = [];
  static var version:String = "0.0.1";
  static var qualityOptions:Array<String> = ['-fastest', '-fast', '-medium', '-thorough', '-exhaustive'];

  public static function main()
  {
    var args = Sys.args().copy();
    COMMAND_CWD = args[args.length - 1];
    args.remove(COMMAND_CWD);

    #if hxp
    switch (System.hostPlatform)
    {
      case WINDOWS:
        astcFile = "astcenc-win.exe";
        CACHE_DIR = Sys.getEnv("TEMP");
      case MAC:
        astcFile = "./astcenc-mac";
        CACHE_DIR = Sys.getEnv("TMPDIR");
      default:
        Sys.println('[Error] Unsupported platform!');
    }
    #end

    if (astcFile == null)
    {
      return;
    }

    if (args.length <= 0 || (args.contains("help") || args.contains("-help") || args.contains("--help")))
    {
      Sys.println('===========================================');
      Sys.println(' ASTC Compressor v$version');
      Sys.println('===========================================');
      Sys.println('');
      Sys.println('Usage:');
      Sys.println('  haxelib run astc-compressor <flags>');
      Sys.println('');
      Sys.println('Arguments:');
      Sys.println('  -i <path>           Path to a PNG file or a folder containing PNG images.');
      Sys.println('  -blocksize <size>   Block size for ASTC compression (e.g., 4x4, 6x6, 8x8).');
      Sys.println('                       Smaller block sizes = better quality, bigger files.');
      Sys.println('  -quality <option>   Compression quality setting:');
      Sys.println('                       -fastest    (lowest quality, fastest encoding)');
      Sys.println('                       -fast       (faster encoding)');
      Sys.println('                       -medium     (default, balanced)');
      Sys.println('                       -thorough   (higher quality, slower)');
      Sys.println('                       -exhaustive (highest quality, very slow)');
      Sys.println('  -premultiply        (Optional) Premultiply alpha before compressing.');
      Sys.println('  -o <output-path>    (Optional) Path to the output directory where compressed textures will be saved.');
      Sys.println('  -excludes <file>    (Optional) Path to a text file that lists files to exclude from compression.');
      Sys.println('');
      Sys.println('Examples:');
      Sys.println('  haxelib run astc-compressor -i ./textures -blocksize 4x4 -quality medium -o ./output');
      Sys.println('  haxelib run astc-compressor -i ./image.png -blocksize 8x8 -quality thorough -premultiply -o ./output');
      Sys.println('  haxelib run astc-compressor -i ./textures -blocksize 6x6 -quality fast -excludes ./excludes.txt');
      Sys.println('');
      Sys.println('Notes:');
      Sys.println('  - Premultiplied alpha is useful for correct blending in some engines.');
      Sys.println('  - Always prefer 4x4 block size for highest visual quality.');
      Sys.println('  - The -o option allows you to specify an output directory for compressed textures.');
      Sys.println('  - The -excludes option lets you exclude specific files from compression by listing them in a text file.');
      Sys.println('  - This tool is shit so please only use ./ for input, output and exclude path.');
      Sys.println('');

      return;
    }

    var path:String = "";
    var cleanPath:String = "";
    var output:String = "";
    var blockSize:String = "";
    var quality:String = "";
    var premultiply:Bool = false;

    var excludedPos:Array<Int> = [];

    for (i in 0...args.length)
    {
      switch (args[i])
      {
        case "-i":
          if (i + 1 < args.length)
          {
            path = cleanPath = args[i + 1];
            excludedPos.push(i + 1);
          }
          else
          {
            Sys.println("Error: No path provided after '-i'");
            return;
          }

        case "-o":
          if (i + 1 < args.length)
          {
            output = args[i + 1];
            excludedPos.push(i + 1);
          }
          else
          {
            Sys.println("Error: No output path provided after '-o'");
            return;
          }

        case "-quality":
          if (i + 1 < args.length)
          {
            quality = "-" + args[i + 1];
            excludedPos.push(i + 1);
          }
          else
          {
            Sys.println("Error: No quality provided after '-quality'");
            return;
          }

        case "-blocksize":
          if (i + 1 < args.length)
          {
            blockSize = args[i + 1];
            excludedPos.push(i + 1);
          }
          else
          {
            Sys.println("Error: No block size provided after '-blocksize'");
            return;
          }

        case "-excludes":
          excludes = parseExcludes(args[i + 1]);
          excludedPos.push(i + 1);
        case "-clean":
          clean = true;
          excludedPos.push(i + 1);

        case "-premultiply":
          premultiply = true;
          excludedPos.push(i + 1);

        default:
          if (!excludedPos.contains(i))
          {
            Sys.println("Unknown argument: " + args[i]);
            return;
          }
      }
    }

    var errored = false;

    if (output.startsWith('./'))
    {
      output = output.replace('./', COMMAND_CWD);
    }

    if (path.startsWith('./'))
    {
      cleanPath = path.substr(2, path.length);

      if (output.length <= 0)
      {
        path = path.replace('./', COMMAND_CWD);
      }
      else
      {
        path = cleanPath;
      }
    }

    if ((!FileSystem.exists(path) && output.length <= 0) || (!FileSystem.exists(COMMAND_CWD + path) && output.length > 0))
    {
      if (output.length <= 0)
        Sys.println('[Error] Invalid path: ' + path);
      else
        Sys.println('[Error] Invalid path: ' + COMMAND_CWD + path);
      errored = true;
    }

    var blockParts = blockSize?.split('x');
    if (blockParts == null || blockParts.length != 2 || !~/^\d+$/.match(blockParts[0]) || !~/^\d+$/.match(blockParts[1]))
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
      compressDirectory(path, cleanPath, output, quality, blockSize, premultiply);
    }
    else
    {
      compressImage(path, cleanPath, output, quality, blockSize, premultiply);
    }
  }

  static function compressDirectory(path:String, cleanPath:String, output:String, quality:String, blockSize:String, premultiply:Bool)
  {
    var dir = output.length > 0 ? COMMAND_CWD + path : path;
    for (entry in FileSystem.readDirectory(dir))
    {
      var newPath = Path.join([path, entry]);
      if (isDirectory(Path.join([dir, entry])))
      {
        compressDirectory(newPath, Path.join([cleanPath, entry]), output, quality, blockSize, premultiply);
      }
      else
      {
        if (entry.endsWith('.png'))
        {
          if (!isExcluded(newPath))
            compressImage(newPath, Path.join([cleanPath, entry]), output, quality, blockSize, premultiply);
        }
      }
    }
  }

  static function compressImage(path:String, cleanPath:String, output:String, quality:String, blockSize:String, premultiply:Bool)
  {
    final outputPath = Path.join([output, Path.withoutExtension(path) + ".astc"]);
    var inputPath = premultiply ? Path.join([CACHE_DIR, "astc-compressor", Path.withoutExtension(Path.withoutDirectory(path)) + "-premultiplied." + Path.extension(path)]) : path;
    if (output.length > 0) inputPath = COMMAND_CWD + inputPath;

    if (FileSystem.exists(inputPath) && !clean) return;

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

    FileSystem.createDirectory(Path.directory(outputPath));
    var proc = new Process(astcFile, ["-cl", inputPath, outputPath, blockSize, quality]);
    proc.close();

    Gc.run(true);

    Sys.println('[✔] ' + (premultiply ? 'Premultiplied and ' : '') + 'compressed "$path" as ASTC ($blockSize, $quality)');
  }

  static function parseExcludes(path:String):Array<String>
  {
    if (path.startsWith('./')) path = path.replace('./', COMMAND_CWD);
    if (!FileSystem.exists(path))
    {
      Sys.println("[ERROR] Could not find exclude file at " + path + ", no exclusions will be applied");
      return [];
    }

    var list = File.getContent(path).trim().split('\n');

		for (i in 0...list.length)
			list[i] = list[i].trim();

    return list;
  }

  static function isExcluded(filePath:String):Bool
  {
    for (exclusion in excludes)
    {
      if (exclusion.endsWith("/*"))
      {
        var normalizedFilePath = Path.normalize(filePath);
        var normalizedExclusion = Path.normalize(exclusion.substr(0, exclusion.length - 2));

        if (normalizedFilePath.startsWith(normalizedExclusion))
          return true;
      }
      else if (exclusion.endsWith("/"))
      {
        var normalizedExclusion = Path.normalize(exclusion);
        var fileDirectory = Path.directory(Path.normalize(filePath));

        if (fileDirectory == normalizedExclusion)
          return true;
      }
      else
      {
        if (filePath == exclusion)
          return true;
      }
    }

    return false;
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
