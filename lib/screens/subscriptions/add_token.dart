// import 'package:bsat/components/header.dart';
// import 'package:bsat/services/payments.dart';
// import 'package:bsat/utils/constants.dart';
// import 'package:flutter/material.dart';

// class AddTokenPage extends StatefulWidget {
//   const AddTokenPage({super.key});

//   @override
//   State<AddTokenPage> createState() => _AddTokenPageState();
// }

// class _AddTokenPageState extends State<AddTokenPage> {
//   final _paymentService = PaymentOps();
//   String _errorCode = "";

//   String _successCode = "";

//   var tokenTextFieldController = TextEditingController();
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Column(
//         mainAxisAlignment: MainAxisAlignment.start,
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           header(context, 'Add Token'),
//           Padding(
//             padding: kPagePaddingInsets,
//             child: Container(
//               padding: kPagePaddingInsets,
//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(kBorderRadius),
//                 color: kLightColor,
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Flex(
//                     direction: Axis.horizontal,
//                     children: [
//                       const Text('Enter Token'),
//                       Text(
//                         " $_errorCode",
//                         style: const TextStyle(
//                           color: kErrorColor,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: kPagePadding / 2),
//                   TextField(
//                     controller: tokenTextFieldController,
//                     decoration: InputDecoration(
//                       hintText: 'abcde0',
//                       border: OutlineInputBorder(
//                         borderRadius: BorderRadius.circular(kBorderRadius),
//                       ),
//                     ),
//                   ),
//                   Text(
//                     "$_successCode ",
//                           style: const TextStyle(
//                       color: kPrimaryColor,
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                   ),
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.end,
//                     children: [
//                       Padding(
//                         padding: const EdgeInsets.symmetric(
//                             vertical: kPagePadding / 2),
//                         child: InkWell(
//                           onTap: () {
//                             _paymentService
//                                 .operateOnCode(tokenTextFieldController.text)
//                                 .then((value) {
//                               if (value == "") {
//                                 setState(() {
//                                   _errorCode = "";
//                                   _successCode = "added successfully";
//                                 });
//                               } else {
//                                 setState(() {
//                                   _errorCode = value;
//                                 });
//                               }
//                             });
//                           },
//                           child: Container(
//                             padding: kPagePaddingInsets / 2,
//                             decoration: BoxDecoration(
//                               color: kPrimaryColor,
//                               borderRadius:
//                                   BorderRadius.circular(kBorderRadius / 2),
//                             ),
//                             child: Text(
//                               'Check',
//                               style: kTitleText.merge(
//                                 const TextStyle(color: kLightColor),
//                               ),
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
