import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/theme.dart';
import '../models/item.dart';
import '../providers/inventory_provider.dart';
import '../services/voice_inventory_service.dart';

class VoiceInventoryScreen extends StatefulWidget {
  const VoiceInventoryScreen({super.key});

  @override
  State<VoiceInventoryScreen> createState() => _VoiceInventoryScreenState();
}

class _VoiceInventoryScreenState extends State<VoiceInventoryScreen>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  late AnimationController _pulseController;
  
  bool _isListening = false;
  bool _isProcessing = false;
  String _accumulatedText = ""; // Accumulated text during session
  String _currentSpeechChunk = ""; // Live chunk
  String _rawText = '';
  List<ParsedCategory> _parsedCategories = [];
  Timer? _audioLevelTimer;
  double _audioLevel = 0.0;
  
  final VoiceInventoryService _service = VoiceInventoryService();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _setupAnimation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioLevelTimer?.cancel();
    _speech.stop();
    super.dispose();
  }

  void _setupAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.8,
      upperBound: 1.2,
    )..repeat(reverse: true);
  }

  /// Get display text (scrolling effect)
  String _getDisplayText() {
    final fullText = (_accumulatedText + ' ' + _currentSpeechChunk).trim();
    
    if (fullText.isEmpty) {
      return _isListening ? "Listening..." : "Tap to Speak";
    }
    
    return fullText;
  }

  void _toggleListening() async {
    if (_isListening) {
      await _stopListeningAndProcess();
    } else {
      await _startListening();
    }
  }

  /// Start continuous listening
  Future<void> _startListening() async {
    bool available = await _speech.initialize(
      onError: (val) {
        debugPrint('🎤 STT Error: $val');
        if (_isListening) {
          debugPrint('🔄 Auto-restarting after error...');
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_isListening) _startSpeechRecognition();
          });
        }
      },
      onStatus: (status) {
        debugPrint('🎤 Status: $status');
        if (_isListening && (status == 'done' || status == 'notListening')) {
          debugPrint('🔄 Auto-restarting to continue listening...');
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_isListening) _startSpeechRecognition();
          });
        }
      },
    );

    if (available) {
      setState(() {
        _isListening = true;
        _accumulatedText = "";
        _currentSpeechChunk = "";
        _audioLevel = 0.3;
      });

      await _startSpeechRecognition();
      _startAudioLevelAnimation();
      debugPrint('🎙️ CONTINUOUS Listening started');
    }
  }

  /// Internal speech recognition start
  Future<void> _startSpeechRecognition() async {
    if (!_isListening) return;
    
    try {
      await _speech.listen(
        onResult: _handleSpeechResult,
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
        localeId: 'en_IN',
        cancelOnError: false,
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('❌ Listen error: $e');
      if (_isListening) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_isListening) _startSpeechRecognition();
        });
      }
    }
  }

  /// Audio level animation
  void _startAudioLevelAnimation() {
    _audioLevelTimer?.cancel();
    
    _audioLevelTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) {
        if (!_isListening) {
          timer.cancel();
          return;
        }
        
        setState(() {
          if (_currentSpeechChunk.isNotEmpty) {
            _audioLevel = 0.6 + (0.4 * (timer.tick % 10) / 10);
          } else {
            _audioLevel = 0.3 + (0.2 * (timer.tick % 10) / 10);
          }
        });
      },
    );
  }

  /// Handle speech results
  void _handleSpeechResult(result) {
    if (!_isListening) return;

    setState(() {
      _currentSpeechChunk = result.recognizedWords;
    });

    if (result.finalResult && _currentSpeechChunk.isNotEmpty) {
      _accumulatedText += _currentSpeechChunk + ' ';
      setState(() {
        _currentSpeechChunk = '';
      });
      debugPrint('📝 Accumulated: $_accumulatedText');
    }
  }

  /// Stop and process
  Future<void> _stopListeningAndProcess() async {
    if (!_isListening) return;

    await _speech.stop();
    _audioLevelTimer?.cancel();

    final finalText = (_accumulatedText + ' ' + _currentSpeechChunk).trim();

    setState(() {
      _isListening = false;
      _accumulatedText = '';
      _currentSpeechChunk = '';
      _audioLevel = 0.0;
    });

    debugPrint('🛑 Stopped. Final text: $finalText');

    if (finalText.isNotEmpty) {
      await _processVoiceInput(finalText);
    }
  }

  Future<void> _processVoiceInput(String text) async {
    setState(() {
      _isProcessing = true;
      _rawText = text;
    });
    
    try {
      final result = await _service.parseVoiceInventory(text);
      
      setState(() {
        _parsedCategories = result;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showNotification('Error processing voice input');
    }
  }

  void _showNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textBlack,
      ),
    );
  }

  void _removeItem(int categoryIndex, int itemIndex) {
    setState(() {
      _parsedCategories[categoryIndex].items.removeAt(itemIndex);
      if (_parsedCategories[categoryIndex].items.isEmpty) {
        _parsedCategories.removeAt(categoryIndex);
      }
    });
  }

  void _addManualItem() {
    setState(() {
      if (_parsedCategories.isEmpty) {
        _parsedCategories.add(ParsedCategory(
          name: 'Other',
          items: [],
        ));
      }
      
      _parsedCategories[0].items.add(ParsedItem(
        name: '',
        price: 0,
        unit: 'kg',
        isExisting: false,
        oldPrice: null,
        oldUnit: null,
        existingId: null,
        aliases: [],
      ));
    });
  }

  void _resetAll() {
    setState(() {
      _rawText = '';
      _currentSpeechChunk = '';
      _parsedCategories = [];
    });
  }

  Future<void> _saveToInventory() async {
    final provider = Provider.of<InventoryProvider>(context, listen: false);
    
    int savedCount = 0;
    int updatedCount = 0;
    
    for (var category in _parsedCategories) {
      for (var item in category.items) {
        // Skip OLD reference items (they're just for comparison)
        if (item.isExisting && item.existingId == null) continue;
        
        // Validate item
        if (item.name.isEmpty || item.price <= 0) continue;
        
        // Use existingId from backend if available (this means it's an update)
        final isUpdate = item.existingId != null && item.existingId!.isNotEmpty;
        
        // Create item with existing ID if found (this will trigger update in backend)
        final newItem = Item(
          id: isUpdate ? item.existingId! : 'custom_${DateTime.now().millisecondsSinceEpoch}_${item.name.toLowerCase().replaceAll(' ', '_')}',
          names: [item.name, ...item.aliases],
          price: item.price,
          unit: item.unit,
          category: category.name,
        );
        
        print('💾 Saving item: ${newItem.id} - ${newItem.names[0]} - ₹${newItem.price}');
        print('   Is update: $isUpdate (existingId: ${item.existingId})');
        
        await provider.addItem(newItem);
        
        if (isUpdate) {
          updatedCount++;
        } else {
          savedCount++;
        }
      }
    }
    
    // Force refresh from backend to ensure UI is in sync
    await provider.fetchItems();
    
    if (mounted) {
      Navigator.pop(context);
      final message = updatedCount > 0 
          ? '$updatedCount item(s) updated, $savedCount new item(s) added'
          : '$savedCount item(s) added to inventory';
      _showNotification(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Lighter blurred background
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              color: Colors.black.withOpacity(0.2), // Much lighter
            ),
          ),
          
          // Centered modal (3/4 screen with equal space top/bottom)
          Center(
            child: Container(
              height: screenHeight * 0.75,
              width: screenWidth * 0.95,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey, width: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Voice Inventory',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  
                  // Voice Button - Green pulsing circle
                  if (_parsedCategories.isEmpty)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        AnimatedScale(
                          scale: _isListening ? 1.0 + (_audioLevel * 0.2) : 1.0,
                          duration: const Duration(milliseconds: 100),
                          child: GestureDetector(
                            onTap: _toggleListening,
                            child: Container(
                              height: 120,
                              width: 120,
                              decoration: BoxDecoration(
                                color: _isListening ? AppColors.primaryGreen : Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isListening ? Colors.transparent : Colors.grey.shade300,
                                  width: 2,
                                ),
                                boxShadow: [
                                  if (_isListening)
                                    BoxShadow(
                                      color: AppColors.primaryGreen.withOpacity(0.5),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                    )
                                  else
                                    const BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                ],
                              ),
                              child: Icon(
                                _isListening ? Icons.graphic_eq : Icons.mic,
                                size: 50,
                                color: _isListening ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            _getDisplayText(),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  
                  // Raw Text Display
                  if (_rawText.isNotEmpty && _parsedCategories.isEmpty)
                    Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _rawText,
                        style: const TextStyle(fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  
                  // Processing Indicator
                  if (_isProcessing)
                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  
                  // Parsed Items List
                  if (_parsedCategories.isNotEmpty && !_isProcessing)
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _parsedCategories.length,
                        itemBuilder: (context, catIndex) {
                          final category = _parsedCategories[catIndex];
                          return _buildCategorySection(category, catIndex);
                        },
                      ),
                    ),
                  
                  // Action Buttons
                  if (_parsedCategories.isNotEmpty && !_isProcessing)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saveToInventory,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('ADD TO INVENTORY', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: _resetAll,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('CANCEL'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Floating Add Button
          if (_parsedCategories.isNotEmpty)
            Positioned(
              right: 30,
              bottom: screenHeight * 0.2,
              child: FloatingActionButton(
                onPressed: _addManualItem,
                backgroundColor: AppColors.primaryGreen,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(ParsedCategory category, int catIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Category: ${category.name}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryGreen,
            ),
          ),
        ),
        ...category.items.asMap().entries.map((entry) {
          final itemIndex = entry.key;
          final item = entry.value;
          return _buildItemRow(item, catIndex, itemIndex);
        }).toList(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildItemRow(ParsedItem item, int catIndex, int itemIndex) {
    return Column(
      children: [
        // OLD item (if exists) - greyed out, non-editable
        if (item.isExisting && item.oldPrice != null)
          Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.all(color: Colors.grey[400]!, width: 1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.name} - ₹${item.oldPrice}/${item.oldUnit ?? item.unit}',
                    style: const TextStyle(
                      color: Colors.grey,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'OLD',
                    style: TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        
        // NEW item - normal color, editable
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.primaryGreen, width: 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              // Header Row
              Row(
                children: [
                  // Remove button
                  IconButton(
                    onPressed: () => _removeItem(catIndex, itemIndex),
                    icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 10),
              
              // Editable Fields
              Row(
                children: [
                  // Price
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: item.price.toString(),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Price',
                        prefixText: '₹',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                      onChanged: (val) {
                        item.price = double.tryParse(val) ?? 0;
                      },
                    ),
                  ),
                  
                  const SizedBox(width: 10),
                  
                  // Unit
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: item.unit,
                      decoration: InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                      onChanged: (val) {
                        item.unit = val;
                      },
                    ),
                  ),
                ],
              ),
              
              // Aliases
              if (item.aliases.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text(
                        'Also: ',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        item.aliases.join(', '),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// Data Models
class ParsedCategory {
  String name;
  List<ParsedItem> items;

  ParsedCategory({
    required this.name,
    required this.items,
  });
}

class ParsedItem {
  String name;
  double price;
  String unit;
  bool isExisting;
  double? oldPrice;
  String? oldUnit;
  String? existingId;
  List<String> aliases;

  ParsedItem({
    required this.name,
    required this.price,
    required this.unit,
    required this.isExisting,
    this.oldPrice,
    this.oldUnit,
    this.existingId,
    required this.aliases,
  });
}
