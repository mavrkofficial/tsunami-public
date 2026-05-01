// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6 <0.8.0;

import '@openzeppelin/contracts/utils/Strings.sol';
import '@uniswap/v3-core/contracts/libraries/BitMath.sol';
import 'base64-sol/base64.sol';

/// @title NFTSVG
/// @notice Generates fully on-chain SVG art for Tsunami V3 LP position NFTs.
///         Forged in SVG for Tsunami — deep ocean aesthetic with animated waves.
///         Each position displays its token pair, fee tier, tick range, and a
///         wave whose amplitude reflects the width of the liquidity range.
library NFTSVG {
    using Strings for uint256;

    // ── Wave S-curves — one full sine cycle (left → right) ──────────────────
    // Amplitude increases with tick range width: calm ripple → massive tsunami.
    // Coordinate space: 145×145 (rendered at transform:translate(72px,189px)).
    // All curves start at x=1,y=72 and end at x=145,y=72 (horizontal baseline).
    string constant curve1 = 'M1 72C25 68 49 76 73 72C97 68 121 76 145 72';   // <=4   ticks - whisper
    string constant curve2 = 'M1 72C25 63 49 81 73 72C97 63 121 81 145 72';   // <=8   ticks - ripple
    string constant curve3 = 'M1 72C25 58 49 86 73 72C97 58 121 86 145 72';   // <=16  ticks - swell
    string constant curve4 = 'M1 72C25 53 49 91 73 72C97 53 121 91 145 72';   // <=32  ticks - wave
    string constant curve5 = 'M1 72C25 48 49 96 73 72C97 48 121 96 145 72';   // <=64  ticks - surge
    string constant curve6 = 'M1 72C25 40 49 104 73 72C97 40 121 104 145 72'; // <=128 ticks - storm
    string constant curve7 = 'M1 72C25 30 49 114 73 72C97 30 121 114 145 72'; // <=256 ticks - typhoon
    string constant curve8 = 'M1 72C25 18 49 126 73 72C97 18 121 126 145 72'; // >256  ticks - tsunami

    struct SVGParams {
        string quoteToken;
        string baseToken;
        address poolAddress;
        string quoteTokenSymbol;
        string baseTokenSymbol;
        string feeTier;
        int24 tickLower;
        int24 tickUpper;
        int24 tickSpacing;
        int8 overRange;
        uint256 tokenId;
        string color0;
        string color1;
        string color2;
        string color3;
        string x1;
        string y1;
        string x2;
        string y2;
        string x3;
        string y3;
    }

    function generateSVG(SVGParams memory params) internal pure returns (string memory svg) {
        return
            string(
                abi.encodePacked(
                    generateSVGDefs(params),
                    generateSVGBorderText(
                        params.quoteToken,
                        params.baseToken,
                        params.quoteTokenSymbol,
                        params.baseTokenSymbol
                    ),
                    generateSVGCardMantle(params.quoteTokenSymbol, params.baseTokenSymbol, params.feeTier),
                    generateSvgCurve(params.tickLower, params.tickUpper, params.tickSpacing, params.overRange),
                    generateSVGPositionDataAndLocationCurve(
                        params.tokenId.toString(),
                        params.tickLower,
                        params.tickUpper
                    ),
                    generateSVGRareSparkle(params.tokenId, params.poolAddress),
                    '</svg>'
                )
            );
    }

    function generateSVGDefs(SVGParams memory params) private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<svg width="290" height="500" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg"',
                " xmlns:xlink='http://www.w3.org/1999/xlink'>",
                '<defs>',
                '<filter id="f1"><feImage result="p0" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><rect width='290px' height='500px' fill='#",
                            params.color0,
                            "'/></svg>"
                        )
                    )
                ),
                '"/><feImage result="p1" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='",
                            params.x1,
                            "' cy='",
                            params.y1,
                            "' r='120px' fill='#",
                            params.color1,
                            "'/></svg>"
                        )
                    )
                ),
                '"/><feImage result="p2" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='",
                            params.x2,
                            "' cy='",
                            params.y2,
                            "' r='120px' fill='#",
                            params.color2,
                            "'/></svg>"
                        )
                    )
                ),
                '" /><feImage result="p3" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='",
                            params.x3,
                            "' cy='",
                            params.y3,
                            "' r='100px' fill='#",
                            params.color3,
                            "'/></svg>"
                        )
                    )
                ),
                '" /><feBlend mode="overlay" in="p0" in2="p1" /><feBlend mode="exclusion" in2="p2" /><feBlend mode="overlay" in2="p3" result="blendOut" /><feGaussianBlur in="blendOut" stdDeviation="42" /></filter>',
                '<clipPath id="corners"><rect width="290" height="500" rx="42" ry="42" /></clipPath>',
                '<path id="text-path-a" d="M40 12 H250 A28 28 0 0 1 278 40 V460 A28 28 0 0 1 250 488 H40 A28 28 0 0 1 12 460 V40 A28 28 0 0 1 40 12 z" />',
                '<path id="minimap" d="M234 444C234 457.949 242.21 463 253 463" />',
                '<filter id="top-region-blur"><feGaussianBlur in="SourceGraphic" stdDeviation="24" /></filter>',
                '<linearGradient id="grad-up" x1="1" x2="0" y1="1" y2="0"><stop offset="0.0" stop-color="white" stop-opacity="1" /><stop offset=".9" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<linearGradient id="grad-down" x1="0" x2="1" y1="0" y2="1"><stop offset="0.0" stop-color="white" stop-opacity="1" /><stop offset="0.9" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<linearGradient id="ocean-floor" x1="0" x2="0" y1="0" y2="1"><stop offset="0.55" stop-color="#00060F" stop-opacity="0" /><stop offset="1" stop-color="#00060F" stop-opacity="0.88" /></linearGradient>',
                '<mask id="fade-up" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="url(#grad-up)" /></mask>',
                '<mask id="fade-down" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="url(#grad-down)" /></mask>',
                '<mask id="none" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="white" /></mask>',
                '<linearGradient id="grad-symbol"><stop offset="0.7" stop-color="white" stop-opacity="1" /><stop offset=".95" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<mask id="fade-symbol" maskContentUnits="userSpaceOnUse"><rect width="290px" height="200px" fill="url(#grad-symbol)" /></mask></defs>',
                '<g clip-path="url(#corners)">',
                '<rect fill="',
                params.color0,
                '" x="0px" y="0px" width="290px" height="500px" />',
                '<rect style="filter: url(#f1)" x="0px" y="0px" width="290px" height="500px" />',
                '<g style="filter:url(#top-region-blur); transform:scale(1.5); transform-origin:center top;">',
                '<rect fill="none" x="0px" y="0px" width="290px" height="500px" />',
                '<ellipse cx="50%" cy="0px" rx="180px" ry="120px" fill="#00060F" opacity="0.92" /></g>',
                '<rect x="0" y="0" width="290" height="500" fill="url(#ocean-floor)" />',
                '<g opacity="0.18"><path d="M-72 448 Q0 428 72 448 Q144 468 216 448 Q288 428 362 448 L362 500 L-72 500 Z" fill="#00A8CC"><animateTransform attributeName="transform" type="translate" from="0 0" to="72 0" dur="6s" repeatCount="indefinite"/></path></g>',
                '<g opacity="0.28"><path d="M-72 458 Q0 440 72 458 Q144 476 216 458 Q288 440 362 458 L362 500 L-72 500 Z" fill="#00D4FF"><animateTransform attributeName="transform" type="translate" from="72 0" to="0 0" dur="4s" repeatCount="indefinite"/></path></g>',
                '<rect x="0" y="0" width="290" height="500" rx="42" ry="42" fill="rgba(0,0,0,0)" stroke="rgba(0,212,255,0.22)" /></g>'
            )
        );
    }

    function generateSVGBorderText(
        string memory quoteToken,
        string memory baseToken,
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol
    ) private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<text text-rendering="optimizeSpeed">',
                '<textPath startOffset="-100%" fill="rgba(0,212,255,0.75)" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                baseToken,
                ' ~ ',
                baseTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" />',
                '</textPath><textPath startOffset="0%" fill="rgba(0,212,255,0.75)" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                baseToken,
                ' ~ ',
                baseTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /> </textPath>',
                '<textPath startOffset="50%" fill="rgba(0,212,255,0.75)" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                quoteToken,
                ' ~ ',
                quoteTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /></textPath>',
                '<textPath startOffset="-50%" fill="rgba(0,212,255,0.75)" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                quoteToken,
                ' ~ ',
                quoteTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /></textPath></text>'
            )
        );
    }

    function generateSVGCardMantle(
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol,
        string memory feeTier
    ) private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<g mask="url(#fade-symbol)"><rect fill="none" x="0px" y="0px" width="290px" height="200px" />',
                '<text y="50px" x="32px" fill="rgba(0,212,255,0.55)" font-family="\'Courier New\', monospace" font-weight="400" font-size="10px" letter-spacing="5">TSUNAMI</text>',
                '<text y="92px" x="32px" fill="white" font-family="\'Courier New\', monospace" font-weight="200" font-size="34px">',
                quoteTokenSymbol,
                '/',
                baseTokenSymbol,
                '</text>',
                '<text y="130px" x="32px" fill="rgba(0,212,255,0.9)" font-family="\'Courier New\', monospace" font-weight="200" font-size="28px">',
                feeTier,
                '</text></g>',
                '<rect x="16" y="16" width="258" height="468" rx="26" ry="26" fill="rgba(0,0,0,0)" stroke="rgba(0,212,255,0.12)" />'
            )
        );
    }

    function generateSvgCurve(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        int8 overRange
    ) private pure returns (string memory svg) {
        string memory fade = overRange == 1 ? '#fade-up' : overRange == -1 ? '#fade-down' : '#none';
        string memory curve = getCurve(tickLower, tickUpper, tickSpacing);
        svg = string(
            abi.encodePacked(
                '<g mask="url(',
                fade,
                ')" style="transform:translate(72px,189px)"><rect x="-16px" y="-16px" width="180px" height="180px" fill="none" /><path d="',
                curve,
                '" stroke="rgba(0,0,0,0.5)" stroke-width="30px" fill="none" stroke-linecap="round" /></g>',
                '<g mask="url(',
                fade,
                ')" style="transform:translate(72px,189px)"><rect x="-16px" y="-16px" width="180px" height="180px" fill="none" /><path d="',
                curve,
                '" stroke="rgba(0,212,255,0.85)" stroke-width="3px" fill="none" stroke-linecap="round" /></g>',
                '<g mask="url(',
                fade,
                ')" style="transform:translate(72px,189px)"><rect x="-16px" y="-16px" width="180px" height="180px" fill="none" /><path d="',
                curve,
                '" stroke="rgba(255,255,255,0.65)" stroke-width="1px" fill="none" stroke-linecap="round" /></g>',
                generateSVGCurveCircle(overRange)
            )
        );
    }

    function getCurve(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing
    ) internal pure returns (string memory curve) {
        int24 tickRange = (tickUpper - tickLower) / tickSpacing;
        if (tickRange <= 4) {
            curve = curve1;
        } else if (tickRange <= 8) {
            curve = curve2;
        } else if (tickRange <= 16) {
            curve = curve3;
        } else if (tickRange <= 32) {
            curve = curve4;
        } else if (tickRange <= 64) {
            curve = curve5;
        } else if (tickRange <= 128) {
            curve = curve6;
        } else if (tickRange <= 256) {
            curve = curve7;
        } else {
            curve = curve8;
        }
    }

    function generateSVGCurveCircle(int8 overRange) internal pure returns (string memory svg) {
        // Endpoint dots at absolute SVG coords.
        // Wave spans x:1->145 at y:72, rendered at translate(72,189).
        // Start abs: (73, 261). End abs: (217, 261).
        string memory curvex1 = '73';
        string memory curvey1 = '261';
        string memory curvex2 = '217';
        string memory curvey2 = '261';
        if (overRange == 1 || overRange == -1) {
            svg = string(
                abi.encodePacked(
                    '<circle cx="',
                    overRange == -1 ? curvex1 : curvex2,
                    'px" cy="',
                    overRange == -1 ? curvey1 : curvey2,
                    'px" r="4px" fill="#00D4FF" /><circle cx="',
                    overRange == -1 ? curvex1 : curvex2,
                    'px" cy="',
                    overRange == -1 ? curvey1 : curvey2,
                    'px" r="24px" fill="none" stroke="#00D4FF" stroke-opacity="0.4" />'
                )
            );
        } else {
            svg = string(
                abi.encodePacked(
                    '<circle cx="',
                    curvex1,
                    'px" cy="',
                    curvey1,
                    'px" r="4px" fill="#00D4FF" />',
                    '<circle cx="',
                    curvex2,
                    'px" cy="',
                    curvey2,
                    'px" r="4px" fill="#00D4FF" />'
                )
            );
        }
    }

    function generateSVGPositionDataAndLocationCurve(
        string memory tokenId,
        int24 tickLower,
        int24 tickUpper
    ) private pure returns (string memory svg) {
        string memory tickLowerStr = tickToString(tickLower);
        string memory tickUpperStr = tickToString(tickUpper);
        uint256 str1length = bytes(tokenId).length + 4;
        uint256 str2length = bytes(tickLowerStr).length + 10;
        uint256 str3length = bytes(tickUpperStr).length + 10;
        (string memory xCoord, string memory yCoord) = rangeLocation(tickLower, tickUpper);
        svg = string(
            abi.encodePacked(
                ' <g style="transform:translate(29px, 384px)">',
                '<rect width="',
                uint256(7 * (str1length + 4)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="rgba(0,16,32,0.72)" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="white"><tspan fill="rgba(0,212,255,0.7)">ID: </tspan>',
                tokenId,
                '</text></g>',
                ' <g style="transform:translate(29px, 414px)">',
                '<rect width="',
                uint256(7 * (str2length + 4)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="rgba(0,16,32,0.72)" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="white"><tspan fill="rgba(0,212,255,0.7)">Min Tick: </tspan>',
                tickLowerStr,
                '</text></g>',
                ' <g style="transform:translate(29px, 444px)">',
                '<rect width="',
                uint256(7 * (str3length + 4)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="rgba(0,16,32,0.72)" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="white"><tspan fill="rgba(0,212,255,0.7)">Max Tick: </tspan>',
                tickUpperStr,
                '</text></g>',
                '<g style="transform:translate(226px, 433px)">',
                '<rect width="36px" height="36px" rx="8px" ry="8px" fill="rgba(0,16,32,0.72)" stroke="rgba(0,212,255,0.25)" />',
                '<path stroke-linecap="round" d="M6 18 Q10 12 14 18 Q18 24 22 18 Q26 12 30 18" fill="none" stroke="rgba(0,212,255,0.8)" stroke-width="1.5"/>',
                '<circle style="transform:translate3d(',
                xCoord,
                'px, ',
                yCoord,
                'px, 0px)" cx="0px" cy="0px" r="4px" fill="#00D4FF"/></g>'
            )
        );
    }

    function tickToString(int24 tick) private pure returns (string memory) {
        string memory sign = '';
        if (tick < 0) {
            tick = tick * -1;
            sign = '-';
        }
        return string(abi.encodePacked(sign, uint256(tick).toString()));
    }

    function rangeLocation(int24 tickLower, int24 tickUpper) internal pure returns (string memory, string memory) {
        int24 midPoint = (tickLower + tickUpper) / 2;
        if (midPoint < -125_000) {
            return ('8', '7');
        } else if (midPoint < -75_000) {
            return ('8', '10.5');
        } else if (midPoint < -25_000) {
            return ('8', '14.25');
        } else if (midPoint < -5_000) {
            return ('10', '18');
        } else if (midPoint < 0) {
            return ('11', '21');
        } else if (midPoint < 5_000) {
            return ('13', '23');
        } else if (midPoint < 25_000) {
            return ('15', '25');
        } else if (midPoint < 75_000) {
            return ('18', '26');
        } else if (midPoint < 125_000) {
            return ('21', '27');
        } else {
            return ('24', '27');
        }
    }

    function generateSVGRareSparkle(uint256 tokenId, address poolAddress) private pure returns (string memory svg) {
        if (isRare(tokenId, poolAddress)) {
            // Rare positions: animated spinning wave-crest medallion
            svg = string(
                abi.encodePacked(
                    '<g style="transform:translate(226px, 392px)">',
                    '<rect width="36px" height="36px" rx="8px" ry="8px" fill="rgba(0,16,32,0.72)" stroke="rgba(0,212,255,0.45)" />',
                    '<g><circle cx="18" cy="18" r="11" fill="none" stroke="#00D4FF" stroke-width="1" stroke-opacity="0.6"/>',
                    '<path style="transform:translate(6px,6px)" d="M0 12 Q3 6 6 12 Q9 18 12 12 Q15 6 18 12 Q21 18 24 12" fill="none" stroke="#00D4FF" stroke-width="1.5" stroke-linecap="round"/>',
                    '<animateTransform attributeName="transform" type="rotate" from="0 18 18" to="360 18 18" dur="8s" repeatCount="indefinite"/>',
                    '</g></g>'
                )
            );
        } else {
            svg = '';
        }
    }

    function isRare(uint256 tokenId, address poolAddress) internal pure returns (bool) {
        bytes32 h = keccak256(abi.encodePacked(tokenId, poolAddress));
        return uint256(h) < type(uint256).max / (1 + BitMath.mostSignificantBit(tokenId) * 2);
    }
}
