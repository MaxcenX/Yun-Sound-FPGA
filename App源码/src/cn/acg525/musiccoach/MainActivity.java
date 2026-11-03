package cn.acg525.musiccoach;

import android.Manifest;
import android.app.*;
import android.os.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.location.LocationManager;
import android.net.Uri;
import android.provider.Settings;
import android.webkit.*;
import android.widget.*;
import android.view.WindowManager;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Offline, bundled UI only. Native BLE, no Internet permission, no remote JS. */
public class MainActivity extends Activity {
 private static final String ORIGIN="https://app.local/";
 private static final UUID SERVICE=UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb"),
  CHANNEL=UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb"),
  CCCD=UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
 private final Handler main=new Handler(Looper.getMainLooper());
 private WebView web;private BluetoothAdapter adapter;private BluetoothLeScanner scanner;
 private BluetoothGatt gatt;private BluetoothGattCharacteristic channel;
 private boolean ready=false,scanning=false,destroyed=false,writing=false;
 private String pendingWrite="",exportText="";
 private AlertDialog picker;private ArrayAdapter<String> list;
 private final ArrayList<BluetoothDevice> devices=new ArrayList<>();
 private Runnable scanTimeout,connectTimeout,writeTimeout;
 @Override public void onCreate(Bundle b){super.onCreate(b);
  getWindow().setStatusBarColor(0xff173c31);getWindow().setNavigationBarColor(0xff173c31);
  getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
  BluetoothManager bm=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE);adapter=bm==null?null:bm.getAdapter();
  web=new WebView(this);setContentView(web);
  WebSettings s=web.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(true);
  s.setAllowFileAccess(false);s.setAllowContentAccess(false);s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
  web.addJavascriptInterface(new Bridge(),"Native");
  web.setWebViewClient(new WebViewClient(){
   @Override public WebResourceResponse shouldInterceptRequest(WebView v,WebResourceRequest r){
    if(r.getUrl().toString().equals(ORIGIN+"index.html"))try{
     return new WebResourceResponse("text/html","UTF-8",getAssets().open("index.html"));
    }catch(IOException e){ }
    return new WebResourceResponse("text/plain","UTF-8",new ByteArrayInputStream(new byte[0]));
   }
   @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){return true;}
  });
  web.loadUrl(ORIGIN+"index.html");
 }
 private void emit(String type,JSONObject value){Runnable delivery=()->{
  if(!destroyed)web.evaluateJavascript("window.nativeEvent&&window.nativeEvent("+JSONObject.quote(type)+","+value.toString()+");",null);
 };if(Looper.myLooper()==Looper.getMainLooper())delivery.run();else main.post(delivery);}
 private JSONObject obj(String k,Object v){JSONObject o=new JSONObject();try{o.put(k,v);}catch(JSONException e){}return o;}
 private void status(String s){emit("status",obj("message",s));}
 private void error(String s){emit("error",obj("message",s));}
 public class Bridge {
  @JavascriptInterface public void connect(){main.post(()->startScan());}
  @JavascriptInterface public void disconnect(){main.post(()->closeLink("已断开，板上曲谱仍可继续跟练"));}
  @JavascriptInterface public void write(String text,String id){main.post(()->writeCommand(text,id));}
  @JavascriptInterface public void exportScore(String text){main.post(()->{
   if(text.length()>100000){error("曲谱过大");return;}exportText=text;
   try{Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("application/json");i.putExtra(Intent.EXTRA_TITLE,"fpga-score.json");startActivityForResult(i,71);}catch(Exception e){error("无法打开文件保存窗口");}
  });}
  @JavascriptInterface public void importScore(){main.post(()->{
   try{Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("*/*");startActivityForResult(i,72);}catch(Exception e){error("无法打开文件选择窗口");}
  });}
 }
 private boolean permissions(){
  ArrayList<String> p=new ArrayList<>();
  if(Build.VERSION.SDK_INT>=31){p.add(Manifest.permission.BLUETOOTH_SCAN);p.add(Manifest.permission.BLUETOOTH_CONNECT);}
  else p.add(Manifest.permission.ACCESS_FINE_LOCATION);
  ArrayList<String> missing=new ArrayList<>();for(String s:p)if(checkSelfPermission(s)!=PackageManager.PERMISSION_GRANTED)missing.add(s);
  if(!missing.isEmpty()){requestPermissions(missing.toArray(new String[0]),61);return false;}return true;
 }
 @Override public void onRequestPermissionsResult(int r,String[] p,int[] results){super.onRequestPermissionsResult(r,p,results);
  if(r==61){for(int a:results)if(a!=PackageManager.PERMISSION_GRANTED){error("未获得蓝牙扫描权限，请在系统应用权限中允许附近设备；旧系统还需定位权限（仅扫描蓝牙）");return;}if(results.length>0)startScan();}
 }
 private void startScan(){
  if(destroyed)return;if(ready){status("已连接，可先点断开再选择设备");return;}if(scanning)return;
  if(adapter==null){error("此设备没有蓝牙适配器");return;}if(!permissions())return;
  try{
   if(!adapter.isEnabled()){startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),62);return;}
   if(Build.VERSION.SDK_INT<31){LocationManager lm=(LocationManager)getSystemService(LOCATION_SERVICE);
    boolean enabled=lm!=null&&(lm.isProviderEnabled(LocationManager.GPS_PROVIDER)||lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER));
    if(!enabled){new AlertDialog.Builder(this).setTitle("蓝牙扫描需要系统位置信息开关").setMessage("此系统版本要求开启位置信息才能扫描BLE。APP不获取或上传坐标，开启后返回并重新连接。").setPositiveButton("打开设置",(d,w)->startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))).setNegativeButton("取消",null).show();return;}
   }
   closeLink(null);devices.clear();list=new ArrayAdapter<>(this,android.R.layout.simple_list_item_1);
   picker=new AlertDialog.Builder(this).setTitle("扫描中：选择你们的JDY-23").setAdapter(list,(d,n)->{BluetoothDevice chosen=devices.get(n);stopScan();connectDevice(chosen);}).setNegativeButton("取消",(d,w)->stopScan()).create();
   picker.setOnCancelListener(d->stopScan());picker.show();
   scanner=adapter.getBluetoothLeScanner();if(scanner==null){error("蓝牙扫描不可用");picker.dismiss();return;}
   scanning=true;scanner.startScan(null,new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),scanCallback);
   status("正在扫描附近BLE设备，请选择自己的JDY-23");
   scanTimeout=()->{stopScan();if(picker!=null&&picker.isShowing())picker.setTitle(devices.isEmpty()?"未发现设备：检查模块供电和旧APP连接":"扫描结束：选择JDY-23");};main.postDelayed(scanTimeout,12000);
  }catch(SecurityException e){error("蓝牙权限被系统拒绝");stopScan();}catch(Exception e){error("扫描失败："+e.getMessage());stopScan();}
 }
 private final ScanCallback scanCallback=new ScanCallback(){
  @Override public void onScanResult(int type,ScanResult result){main.post(()->{
   if(!scanning)return;BluetoothDevice d=result.getDevice();for(BluetoothDevice x:devices)if(x.getAddress().equals(d.getAddress()))return;
   if(devices.size()>=60)return;String name=result.getScanRecord()==null?null:result.getScanRecord().getDeviceName();
   if(name==null)name="未命名BLE设备";devices.add(d);list.add(name+"  "+d.getAddress()+"  "+result.getRssi()+"dBm");
  });}
  @Override public void onScanFailed(int code){main.post(()->{stopScan();error("扫描失败，系统代码"+code+"；请稍后重试");});}
 };
 private void stopScan(){if(scanTimeout!=null)main.removeCallbacks(scanTimeout);if(scanning&&scanner!=null)try{scanner.stopScan(scanCallback);}catch(Exception ignored){}scanning=false;}
 private void connectDevice(BluetoothDevice d){
  status("正在连接并开启FFE1通知…");
  try{gatt=d.connectGatt(this,false,gattCallback,BluetoothDevice.TRANSPORT_LE);
   connectTimeout=()->{if(!ready)closeLink("连接超时：检查是否被其他APP占用");};main.postDelayed(connectTimeout,15000);
  }catch(Exception e){closeLink("连接失败："+e.getMessage());}
 }
 private final BluetoothGattCallback gattCallback=new BluetoothGattCallback(){
  @Override public void onConnectionStateChange(BluetoothGatt g,int code,int state){main.post(()->{
   if(g!=gatt)return;if(code!=BluetoothGatt.GATT_SUCCESS||state==BluetoothProfile.STATE_DISCONNECTED){closeLink("蓝牙断开，状态码"+code);return;}
   if(state==BluetoothProfile.STATE_CONNECTED)try{if(!g.discoverServices())closeLink("无法发现蓝牙服务");}catch(Exception e){closeLink("服务发现权限失败");}
  });}
  @Override public void onServicesDiscovered(BluetoothGatt g,int code){main.post(()->{
   if(g!=gatt)return;BluetoothGattService service=g.getService(SERVICE);
   if(code!=0||service==null){closeLink("未找到FFE0服务，请确认是JDY-23透传模块");return;}
   channel=service.getCharacteristic(CHANNEL);
   if(channel==null||(channel.getProperties()&(BluetoothGattCharacteristic.PROPERTY_WRITE|BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE))==0){closeLink("FFE1不支持写入");return;}
   BluetoothGattDescriptor cccd=channel.getDescriptor(CCCD);
   if(cccd==null){closeLink("FFE1缺少通知描述符");return;}
   try{
    if(!g.setCharacteristicNotification(channel,true)){closeLink("开启通知失败");return;}
    if((channel.getProperties()&BluetoothGattCharacteristic.PROPERTY_NOTIFY)!=0)cccd.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
    else if((channel.getProperties()&BluetoothGattCharacteristic.PROPERTY_INDICATE)!=0)cccd.setValue(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE);
    else {closeLink("FFE1没有通知功能");return;}
    if(!g.writeDescriptor(cccd))closeLink("通知订阅提交失败");
   }catch(Exception e){closeLink("订阅通知失败："+e.getMessage());}
  });}
  @Override public void onDescriptorWrite(BluetoothGatt g,BluetoothGattDescriptor d,int code){main.post(()->{
   if(g!=gatt||!CCCD.equals(d.getUuid()))return;if(code!=0){closeLink("通知订阅失败："+code);return;}
   try{g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);}catch(Exception ignored){}
   ready=true;main.removeCallbacks(connectTimeout);emit("connected",obj("name","JDY-23"));
  });}
  @Override public void onCharacteristicChanged(BluetoothGatt g,BluetoothGattCharacteristic c){byte[] bytes=c.getValue();if(bytes!=null)notifyData(g,c.getUuid(),bytes.clone());}
  @Override public void onCharacteristicChanged(BluetoothGatt g,BluetoothGattCharacteristic c,byte[] value){notifyData(g,c.getUuid(),value.clone());}
  @Override public void onCharacteristicWrite(BluetoothGatt g,BluetoothGattCharacteristic c,int code){main.post(()->{
   if(g!=gatt||!writing)return;if(writeTimeout!=null)main.removeCallbacks(writeTimeout);
   String id=pendingWrite;writing=false;emit(code==0?"written":"writeError",obj("id",id));
  });}
 };
 private void notifyData(BluetoothGatt g,UUID uuid,byte[] value){final long arrivedAt=System.currentTimeMillis();main.post(()->{
  if(g!=gatt||!ready||!uuid.equals(CHANNEL))return;JSONArray a=new JSONArray();for(byte b:value)a.put(b&255);JSONObject payload=obj("bytes",a);try{payload.put("arrivedAt",arrivedAt);}catch(JSONException ignored){}emit("data",payload);
 });}
 private void writeCommand(String text,String id){
  if(!ready||gatt==null||channel==null||writing){emit("writeError",obj("id",id));return;}
  // Restrict the native bridge to the project's short ASCII protocol.
  if(!text.matches("[A-Z0-9?;]{2,20}")||!text.endsWith(";")){emit("writeError",obj("id",id));return;}
  try{channel.setWriteType((channel.getProperties()&BluetoothGattCharacteristic.PROPERTY_WRITE)!=0?BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT:BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
   channel.setValue(text.getBytes(StandardCharsets.US_ASCII));writing=true;pendingWrite=id;
   if(!gatt.writeCharacteristic(channel)){writing=false;emit("writeError",obj("id",id));return;}
   writeTimeout=()->{if(writing){writing=false;emit("writeError",obj("id",id));closeLink("蓝牙写入超时，请重新连接");}};main.postDelayed(writeTimeout,2500);
  }catch(Exception e){writing=false;emit("writeError",obj("id",id));}
 }
 private void closeLink(String reason){
  stopScan();ready=false;writing=false;channel=null;
  if(connectTimeout!=null)main.removeCallbacks(connectTimeout);if(writeTimeout!=null)main.removeCallbacks(writeTimeout);
  BluetoothGatt old=gatt;gatt=null;if(old!=null)try{old.disconnect();old.close();}catch(Exception ignored){}
  if(reason!=null)emit("disconnected",obj("message",reason));
 }
 @Override protected void onActivityResult(int req,int result,Intent data){super.onActivityResult(req,result,data);
  if(req==62){if(result==RESULT_OK)startScan();else error("需要打开蓝牙后才能连接");return;}
  if(result!=RESULT_OK||data==null||data.getData()==null)return;
  Uri uri=data.getData();try{
   if(req==71){try(OutputStream o=getContentResolver().openOutputStream(uri)){if(o==null)throw new IOException("无法写入文件");o.write(exportText.getBytes(StandardCharsets.UTF_8));}status("曲谱已导出，请妥善保留备份");}
   if(req==72){try(InputStream in=getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){
    if(in==null)throw new IOException("无法读取文件");byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){if(out.size()+n>100000)throw new IOException("文件超过100KB");out.write(b,0,n);}emit("import",obj("text",new String(out.toByteArray(),StandardCharsets.UTF_8)));}}
  }catch(Exception e){error("文件操作失败："+e.getMessage());}
 }
 @Override protected void onStop(){super.onStop();stopScan();}
 @Override protected void onDestroy(){destroyed=true;closeLink(null);main.removeCallbacksAndMessages(null);if(web!=null){web.removeJavascriptInterface("Native");web.destroy();}super.onDestroy();}
}
