# dartkiteticker

#Example using KiteTicker 

The WebSocket API is the most efficient (speed, latency, resource consumption, and bandwidth) way to receive quotes for instruments across all exchanges during live market hours. A quote consists of fields such as open, high, low, close, last traded price, 5 levels of bid/offer market depth data etc.


```dart
// Create an KiteTicker instance with apikey and accesskey
 ticker = KiteTicker(apikey:"xxxx",accesstoken:"xxxxx");
 
 //Listener set for each tick
 ticker.stream listen((List<dynamic> event){
 
 //data quotes
 print(event);
 });
 
 //Subscribe to instruments_list
 ticker.subscribe([instrument_token]);
 ```
