import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:great_circle_distance/great_circle_distance.dart';
import 'package:rider/services/censor.dart';
import 'package:rider/services/firebase_analytics.dart';
import 'package:rider/utils/text_styles.dart';
import 'package:rider/utils/ui_helpers.dart';
import 'package:rider/widgets/message.dart';
import 'package:rider/widgets/message_placeholder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyChatPage extends StatefulWidget {
  final SharedPreferences helper;
  final int nearbyRiders;
  final LatLng location;
  final String destination;
  MyChatPage(
      {Key key,
      @required this.helper,
      @required this.nearbyRiders,
      @required this.location,
      @required this.destination})
      : super(key: key);

  @override
  _MyChatPageState createState() => _MyChatPageState();
}

class _MyChatPageState extends State<MyChatPage> {
  bool noHotspotMessages = true;
  bool isScrollDownVisible1 = true;
  bool isScrollDownVisible2 = true;
  ScrollController _scrollController = ScrollController();
  TextEditingController _messageController1 = TextEditingController();
  TextEditingController _messageController2 = TextEditingController();
  final messageExpireInterval =
      Duration(hours: 1); // timeout to delete old messages

  void _scrollDown() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      curve: Curves.easeOut,
      duration: Duration(milliseconds: 300),
    );
  }

  Message _messageChecker(DocumentSnapshot doc, List<DocumentSnapshot> docs,
      String identity, String chatroom, LatLng myLocation) {
    bool isNear = false;
    final chatRadius = 100.0;
    final messageTimestamp = doc.data['timestamp'].toDate();
    final timeDiff = DateTime.now().difference(messageTimestamp);
    final messageLocation = LatLng(doc.data['location']['geopoint'].latitude,
        doc.data['location']['geopoint'].longitude);

    if (timeDiff > messageExpireInterval) {
      // if expired, delete the message
      final documentId = doc.documentID;
      Firestore.instance.collection(chatroom).document(documentId).delete();
      if (docs.length <= 1) {
        return Message(
          isMe: identity == doc.data['senderId'],
          isNear: false,
          senderId: null,
          senderName: null,
          messageText: null,
          destination: null,
          location: messageLocation,
          timestamp: messageTimestamp,
        );
      }
    } else {
      if (chatroom == 'hotspot_chat') {
        final messageDistance = GreatCircleDistance.fromDegrees(
          latitude1: myLocation.latitude,
          longitude1: myLocation.longitude,
          latitude2: messageLocation.latitude,
          longitude2: messageLocation.longitude,
        ).haversineDistance(); // no futures here!

        if (chatRadius >= messageDistance) {
          // display if nearby
          isNear = true;
          noHotspotMessages = false;
        }
      }
      return Message(
        isMe: identity == doc.data['senderId'],
        isNear: chatroom == 'hotspot_chat' ? isNear : true,
        senderId: doc.data['senderId'],
        senderName: doc.data['senderName'],
        messageText: doc.data['messageText'],
        destination: doc.data['destination'],
        location: messageLocation,
        timestamp: messageTimestamp,
      );
    }
  }

  Future<void> _sendMessage(TextEditingController messageController,
      String chatroom, LatLng location, String destination) async {
    String name = widget.helper.getString('userName');
    String identity = widget.helper.getString('uuid');
    String messageText = messageController.text;

    messageController.clear();

    if (messageText.length > 0) {
      GeoFirePoint geoPoint = Geoflutterfire()
          .point(latitude: location.latitude, longitude: location.longitude);
      messageText = censor(messageText);

      await Firestore.instance.collection(chatroom).add({
        'senderId': identity,
        'senderName': name,
        'messageText': messageText,
        'destination': destination,
        'location': geoPoint.data,
        'timestamp': DateTime.now(),
      });
      _scrollDown();
      logAnalyticsEvent('message_sent_$chatroom');
    }
  }

  @override
  Widget build(BuildContext context) {
    String identity = widget.helper.getString('uuid');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: invertInvertColorsStrong(context),
        appBar: PreferredSize(
          preferredSize: Size(100.0, 120.0),
          child: Padding(
            padding: EdgeInsets.only(
              top: 40.0,
              left: 15.0,
              right: 15.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios),
                      tooltip: 'Go back',
                      iconSize: 20.0,
                      color: invertColorsStrong(context),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                    Text(
                      'Chat',
                      style: isThemeCurrentlyDark(context)
                          ? TitleStyles.white
                          : TitleStyles.black,
                    ),
                  ],
                ),
                TabBar(
                  tabs: [
                    Tab(
                      child: Text(
                        'Hotspot Chat',
                        style: isThemeCurrentlyDark(context)
                            ? LabelStyles.white
                            : LabelStyles.black,
                      ),
                    ),
                    Tab(
                      child: Text(
                        'Global Chat',
                        style: isThemeCurrentlyDark(context)
                            ? LabelStyles.white
                            : LabelStyles.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            Container(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 15.0,
                        right: 15.0,
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: Firestore.instance
                            .collection('hotspot_chat')
                            .orderBy('timestamp')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return messagePlaceholder(
                                context, 'Loading messages...');

                          List<DocumentSnapshot> docs = snapshot.data.documents;

                          List<Widget> messages = docs
                              .map((doc) => _messageChecker(doc, docs, identity,
                                  'hotspot_chat', widget.location))
                              .toList();

                          if (noHotspotMessages)
                            return messagePlaceholder(
                                context,
                                widget.nearbyRiders == 1
                                    ? 'No Riders nearby to chat with!'
                                    : 'Chat with ${widget.nearbyRiders - 1} others near you');

                          return Stack(
                            children: <Widget>[
                              ListView(
                                controller: _scrollController,
                                children: <Widget>[
                                  ...messages,
                                ],
                              ),
                              Positioned(
                                bottom: 10.0,
                                right: 7.5,
                                child: Visibility(
                                  visible: isScrollDownVisible1,
                                  child: FloatingActionButton(
                                    mini: true,
                                    child: Icon(Icons.keyboard_arrow_down),
                                    foregroundColor:
                                        invertInvertColorsTheme(context),
                                    backgroundColor: invertColorsTheme(context),
                                    onPressed: () {
                                      _scrollDown();
                                      setState(() {
                                        isScrollDownVisible1 = false;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 10.0,
                  ),
                  Container(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 15.0,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController1,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Message in hotspot chat',
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: invertColorsStrong(context),
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: invertColorsTheme(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 15.0,
                        ),
                        FloatingActionButton(
                          heroTag: 'chat',
                          foregroundColor: invertInvertColorsTheme(context),
                          backgroundColor: invertColorsTheme(context),
                          child: Icon(Icons.send),
                          elevation: 5.0,
                          tooltip: 'Send',
                          onPressed: () {
                            _sendMessage(_messageController1, 'hotspot_chat',
                                widget.location, widget.destination);
                            setState(() {
                              isScrollDownVisible1 = false;
                            });
                          },
                        ),
                        SizedBox(
                          width: 15.0,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 10.0,
                  ),
                ],
              ),
            ),
            Container(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 15.0,
                        right: 15.0,
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: Firestore.instance
                            .collection('global_chat')
                            .orderBy('timestamp')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return messagePlaceholder(
                                context, 'Loading messages...');

                          List<DocumentSnapshot> docs = snapshot.data.documents;

                          if (docs.isEmpty)
                            return messagePlaceholder(context,
                                'Chat with all Fliver users\nto discuss traffic issues etc.');

                          List<Widget> messages = docs
                              .map((doc) => _messageChecker(doc, docs, identity,
                                  'global_chat', widget.location))
                              .toList();

                          return Stack(
                            children: <Widget>[
                              ListView(
                                controller: _scrollController,
                                children: <Widget>[
                                  ...messages,
                                ],
                              ),
                              Positioned(
                                bottom: 10.0,
                                right: 7.5,
                                child: Visibility(
                                  visible: isScrollDownVisible2,
                                  child: FloatingActionButton(
                                    mini: true,
                                    child: Icon(Icons.keyboard_arrow_down),
                                    foregroundColor:
                                        invertInvertColorsTheme(context),
                                    backgroundColor: invertColorsTheme(context),
                                    onPressed: () {
                                      _scrollDown();
                                      setState(() {
                                        isScrollDownVisible2 = false;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 10.0,
                  ),
                  Container(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 15.0,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController2,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Message in global chat',
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: invertColorsStrong(context),
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: invertColorsTheme(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 15.0,
                        ),
                        FloatingActionButton(
                          heroTag: 'chat',
                          foregroundColor: invertInvertColorsTheme(context),
                          backgroundColor: invertColorsTheme(context),
                          child: Icon(Icons.send),
                          elevation: 5.0,
                          tooltip: 'Send',
                          onPressed: () {
                            _sendMessage(_messageController2, 'global_chat',
                                widget.location, null);
                            setState(() {
                              isScrollDownVisible2 = false;
                            });
                          },
                        ),
                        SizedBox(
                          width: 15.0,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 10.0,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
