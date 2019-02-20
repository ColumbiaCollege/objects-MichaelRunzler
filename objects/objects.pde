// Ethan R. Scott

import java.io.FileOutputStream;
import java.util.Arrays;
import java.util.stream.Stream;
import java.util.Iterator;
import javax.swing.JOptionPane.*;

import static javax.swing.JOptionPane.*;

ASCIIImage active;
boolean done; // Flag is set if program has successfully completed processing
boolean abort; // Flag is set if user has aborted a dialog, signaling for program exit

void settings()
{
  size(100, 100);
}

void setup()
{
  // Initial setup
  background(0);
  active = null;
  done = false;
  abort = false;
  
  // Delegate to dialog tree subthread
  loop(true);
  
  // Wait for either flag to be set
  while(!done && !abort) delay(500);
  
  // Only show completion message if the user did not abort
  if(done) showMessageDialog(null, "Save complete. Program will now exit.");
  
  // Exit the program automatically, since there is nothing else to do
  exit();
}

void loadExtImage(File selected)
{
  // If the user clicks cancel, set the abort flag and return straight to the main thread
  if(selected == null){
    abort = true;
    return;
  }
  
  // If the selected file does not exist, re-show the dialog
  if(!selected.exists()){
    showMessageDialog(null, "Selected file has been moved or deleted. Try again.");
    loop(true);
    return;
  }
  
  // Load the image. If the load fails, re-show the dialog.
  PImage loaded = loadImage(selected.getAbsolutePath());
  if(loaded == null) {
    showMessageDialog(null, "Image load failed! Try again.");
    loop(true);
    return;
  }
  
  // Ask the user for a scaling factor. If the user clicks cancel, set the abort flag and return to the main thread
  // Generate scale factor list.
  Object[] values = new Object[40];
  for(int i = 0; i < values.length; i++) values[i] = "" + (i + 1) + ":1";
  Object res = showInputDialog(null, "Select Scale Factor", "Select a scale factor (input:output) for the output image.", INFORMATION_MESSAGE, null, values, values[1]);
  if(res == null){
    abort = true;
    return;
  }
  
  // Run a comparison to figure out which option the user picked.
  int scale = 2;
  for(int i = 0; i < values.length; i++){
    if((String)values[i] == (String)res){
      scale = i + 1;
      break;
    }
  }
  
  // Construct and process the ASCII representation of the loaded image, then delegate to the save-file dialog tree.
  active = new ASCIIImage(loaded);
  active.process(scale);
  loop(false);
}

void saveToFile(File selected)
{
  // If the user clicks cancel, set the abort flag and return straight to the main thread
  if(selected == null){
    abort = true;
    return;
  }
  
  // If the file exists, and cannot be deleted, re-show the dialog
  if(selected.exists() && !selected.delete()){
    showMessageDialog(null, "Cannot overwrite existing file. Try again.");
    loop(false);
    return;
  }
  
  // Ensure that the destination file has either (a) no file extension, or (b) a .txt/.rtf extension
  String ext = selected.getName();
  if(ext.contains(".")) ext = ext.substring(ext.lastIndexOf('.'), ext.length());
  
  // If the extension does not match any of the recognized formats, tag a .txt extension onto it.
  if(!ext.contains(".") || !(ext.equals(".txt") || ext.equals(".rtf"))){
    selected = new File(selected.getParentFile(), selected.getName() + ".txt");
  }
  
  // Let the user know that the program has not frozen - it's just working in the background.
  showMessageDialog(null, "Program working...");
  
  // Write the ASCII image to file.
  try{
    // Open a stream to the file
    FileOutputStream fos = new FileOutputStream(selected);
    
    // Iterate through each row in the image
    Iterator<char[]> iter = active.toStream().iterator();
    while(iter.hasNext())
    {
      // Write boundary character to 'frame' the image, then the line data
      fos.write('|');
      for(char c : iter.next())
        fos.write(c);
      
      // Write another boundary character, then a CRLF newline
      fos.write('|');
      fos.write('\r');
      fos.write('\n');
    }
    
    // Close the file stream
    fos.flush();
    fos.close();
  } catch(IOException e){
    // If the program encounters an IO error, re-show the save dialog
    showMessageDialog(null, "I/O error while saving file - choose another file and try again.");
    e.printStackTrace();
    loop(false);
    return;
  }
  
  // If this point is reached, the file write completed successfully, set the 'done' flag and return to the main thread.
  done = true;
}

void loop(boolean loadOrSave){
  // Delegation method used for enabling multiple-try dialogs and soft-error handling.
  // Delegates to the appropriate method in another thread after accepting user input.
  if(loadOrSave) selectInput("Select an image file to load...", "loadExtImage");
  else selectOutput("Save the output file where?", "saveToFile");
}

// Converts a bitshifted ARGB color to a four-entry 8bpp ARGB array.
public static int[] toARGB(int c){
    return new int[]{(c >> 24) & 0xff, (c >> 16) & 0xff, c >> 8 & 0xff, c & 0xff};
}

// Converts a four-entry 8bpp ARGB array to a 32-bit bitshifted color value.
public static int fromARGB(int[] ARGB){
    return ((ARGB[0] & 0xff) << 24 | (ARGB[1] & 0xff) << 16 | (ARGB[2] & 0xff) << 8 | (ARGB[3] & 0xff));
}


/**
 * Loads, generates, stores, and manipulates and ASCII representation of a standard raster image.
 */
class ASCIIImage
{
  private char[][] pixels; // first dimension is Y, second is X
  private PImage src; // Copy of original image, changes do not carry over
  
  /**
   * Standard constructor.
   * @param src a PImage to use as the source for this ASCII image.
   *            The source image is copied in the constructor, and no reference to the original is held.
   */
  public ASCIIImage(PImage src)
  {
    // Create blank image with the same dimensions as the source
    this.src = createImage(src.width, src.height, ARGB);
    
    // Populate pixel map in the source image, and copy each pixel over to the local copy
    src.loadPixels();
    for(int i = 0; i < src.pixels.length; i++) this.src.pixels[i] = src.pixels[i];
    
    // Apply filters to the local copy of the source image
    this.src.filter(POSTERIZE, 4);
    this.src.filter(GRAY);
    
    // Initialize ASCII pixel storage array with the same dimensions as the source - this is only used for preventing exceptions
    // from being generated from calls to other methods before process() is called.
    pixels = new char[src.height][src.width];
  }
  
  /**
   * Processes the stored raster image into its ASCII counterpart.
   * @param scaleFactor the scaling ratio (n:1) to use for the output image.
   */
  public void process(int scaleFactor)
  {
    // Determine (approximate) aspect ratio of the source image.
    //The ratio is lower-bounded at 2, since smaller values distort the aspect 
    // ratio of the source image due to the asymmetrical nature of ASCII character displays.
    int ratio = Math.round((float)src.width / (float)src.height);
    if(ratio < 2) ratio = 2;
    
    // Blank and resize ASCII pixel array to match the width and height of the source image, scaled by the scale factor and adjusted to match aspect ratio.
    pixels = new char[(int)Math.ceil((double)src.height / (double)scaleFactor)][(int)Math.ceil((double)src.width / (double)scaleFactor) * ratio];
    
    // Debug output
    println("Set scaling factor: " + scaleFactor + ":1");
    println("Adjusted aspect ratio: 1:" + ratio);
    println(String.format("Source image size: (%d, %d)", src.width, src.height));
    println(String.format("ASCII pixel array dimensions: (%d, %d)", pixels[0].length, pixels.length));
    
    // Iterate through each character in the ASCII pixel array
    for(int y = 0; y < pixels.length; y++){
      for(int x = 0; x < pixels[y].length; x++)
      {
        // Get the average of all of the pixel colors in the scaled area
        int avg = average(x * scaleFactor, y * scaleFactor, scaleFactor, scaleFactor);
        
        // Generate ASCII character from the averaged color value
        char res = fromColor(avg);
        
        // Scale the output to match the aspect ratio: copy the derived character to multiple X-value pixels
        for(int i = 0; i < ratio; i++){
          if((x * ratio) + i >= pixels[y].length) break;
          pixels[y][(x * ratio) + i] = res;
        }
      }
    }
  }
  
  /**
   * Gets the character at a specified X,Y value.
   */
  public char pixelAt(int x, int y){
    if(x >= pixels[y].length || y >= pixels.length) throw new IllegalArgumentException("X or Y value out of bounds!");
    return pixels[y][x];
  }
  
  /**
   * Sets the character at the specified X,Y value to the provided character.
   */
  public void setPixelAt(int x, int y, char c){
    pixels[y][x] = c;
  }
  
  /**
   * Gets the ASCII pixel array in stream form. Each element in the stream is a single line of pixels,
   * streaming them in order will result in a complete picture.
   */
  public Stream<char[]> toStream(){
    return Arrays.stream(pixels);
  }
  
  // Averages the pixel color values in the area starting at (startX, startY) with side lengths (xLen, yLen).
  private int average(int startX, int startY, int xLen, int yLen)
  {
    int[] values = new int[xLen * yLen];
    
    // Sample the red value of each pixel in the sampled area and store it sequentially in the cache array
    for(int x = startX; x < (startX + xLen); x++){
      for(int y = startY; y < (startY + yLen); y++){
        if(x >= src.width || y >= src.height) values[((x - startX) * xLen) + (y - startY)] = color(255);
        values[((x - startX) * xLen) + (y - startY)] = src.get(x, y);
      }
    }
    
    // Total sampled values and divide by the number of samples
    int ttl = 0;
    for(int v : values) ttl += toARGB(v)[1];
    ttl /= values.length;
    
    return ttl;
  }
  
  // Returns a character approximating the given color value.
  private char fromColor(int e)
  {
    if(e > 16 && e < 64)
      return '.';
    else if(e > 0 && e <= 64)
      return 'X';
    else if(e > 64 && e <= 128)
      return '#';
    else if(e > 128 && e <= 192)
      return '0';
    else if(e > 192 && e <= 255)
      return '@';
    else return ' ';
  }
}
