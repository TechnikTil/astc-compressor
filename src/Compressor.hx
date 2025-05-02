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

class Compressor
{
  static var LIB_CWD:String;
  static var astcFile:String = null;
  static var clean:Bool = false;
  static var excludes:Array<String> = [];
  static var version:String = "0.1.0";
  static var qualityOptions:Array<String> = ['-fastest', '-fast', '-medium', '-thorough', '-exhaustive'];

  public static function main()
  {
    var args = Sys.args().copy();
    LIB_CWD = Sys.getCwd();
    Sys.setCwd(args.pop());

    #if hxp
    switch (System.hostPlatform)
    {
      case WINDOWS:
        astcFile = Path.join([LIB_CWD, "astcenc-win.exe"]);
      case MAC:
        astcFile = Path.join([LIB_CWD, "./astcenc-mac"]);
        if (!FileSystem.exists(astcFile))
        {
          Sys.println('[Error] Could not find the ASTC CLI tool.');
          Sys.println('        Please make sure you\'ve downloaded the MAC ASTC CLI and from https://github.com/ARM-software/astc-encoder/releases/tag/5.2.0 and have put it at $astcFile.');
          astcFile = null;
        }
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
      logHelp();
      return;
    }

    var path:String = "";
    var output:String = "";
    var blockSize:String = "";
    var quality:String = "";

    var excludedPos:Array<Int> = [];

    for (i in 0...args.length)
    {
      switch (args[i])
      {
        case "-i":
          if (i + 1 < args.length)
          {
            path = args[i + 1];
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

        default:
          if (!excludedPos.contains(i))
          {
            Sys.println("Unknown argument: " + args[i]);
            return;
          }
      }
    }

    var errored = false;

    if (!FileSystem.exists(path))
    {
      Sys.println('[Error] Invalid path: ' + FileSystem.absolutePath(path));
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
      compressDirectory(path, output, quality, blockSize);
    }
    else
    {
      compressImage(path, output, quality, blockSize);
    }
  }

  static function compressDirectory(path:String, output:String, quality:String, blockSize:String, EntryPath:String = '')
  {
    for (entry in FileSystem.readDirectory(path))
    {
      final entryPath = Path.join([EntryPath, entry]);
      final entryInputPath = Path.join([path, entry]);
      final entryOutputPath = Path.join([output, entry]);

      if (isDirectory(entryInputPath))
      {
        compressDirectory(entryInputPath, entryOutputPath, quality, blockSize, entryPath);
      }
      else
      {
        if (entry.endsWith('.png') && !isExcluded(entryInputPath))
        {
          compressImage(entryInputPath, entryOutputPath, quality, blockSize, entryPath);
        }
      }
    }
  }

  static function compressImage(path:String, output:String, quality:String, blockSize:String, entryPath:String = '')
  {
    final outputPath = Path.withoutExtension(output) + ".astc";
    final inputPath = path;

    if (FileSystem.exists(outputPath) && !clean) return;

    FileSystem.createDirectory(Path.directory(outputPath));
    var proc = new Process(astcFile, ["-cl", inputPath, outputPath, blockSize, quality]);
    proc.close();

    Gc.run(false);

    Sys.println('[✔] compressed "$path" as ASTC ($blockSize, $quality)');
  }

  static function logHelp():Void
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
    Sys.println('  -o <output-path>    (Optional) Path to the output directory where compressed textures will be saved.');
    Sys.println('  -excludes <file>    (Optional) Path to a text file that lists files to exclude from compression.');
    Sys.println('  -clean              (Optional) Compress all images in the input path regardless if they already are.');
    Sys.println('');
    Sys.println('Examples:');
    Sys.println('  haxelib run astc-compressor -i ./textures -blocksize 4x4 -quality medium -o ./output');
    Sys.println('  haxelib run astc-compressor -i ./image.png -blocksize 8x8 -quality thorough -o ./output -clean');
    Sys.println('  haxelib run astc-compressor -i ./textures -blocksize 6x6 -quality fast -excludes ./excludes.txt');
    Sys.println('');
    Sys.println('Notes:');
    Sys.println('  - Always prefer 4x4 block size for highest visual quality.');
    Sys.println('  - The -o option allows you to specify an output directory for compressed textures.');
    Sys.println('  - The -excludes option lets you exclude specific files from compression by listing them in a text file.');
    Sys.println('  - This tool is shit so please only use ./ for input, output and exclude path.');
    Sys.println('');
  }

  static function parseExcludes(path:String):Array<String>
  {
    if (!FileSystem.exists(path))
    {
      Sys.println("[ERROR] Could not find exclude file at " + FileSystem.absolutePath(path) + ", no exclusions will be applied");
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
        {
          return true;
        }
      }
      else if (exclusion.endsWith("/"))
      {
        var normalizedExclusion = Path.normalize(exclusion);
        var fileDirectory = Path.directory(Path.normalize(filePath));

        if (fileDirectory == normalizedExclusion)
        {
          return true;
        }
      }
      else
      {
        if (filePath == exclusion)
        {
          return true;
        }
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
