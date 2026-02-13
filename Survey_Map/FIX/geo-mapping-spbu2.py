import pandas as pd
import json
import os

# Read the Excel file
excel_path = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/FIX/SPBUN_Terpilih.xlsx"
# Read from the 'Data' sheet
try:
    df = pd.read_excel(excel_path, sheet_name='SPBUN Terpilih')
except:
    # Fallback to first sheet if 'Data' sheet doesn't exist
    df = pd.read_excel(excel_path, sheet_name=0)

# Parse coordinates from the "Koordinat" column
def parse_coordinates(coord_str):
    """Parse coordinates from string format 'lat,lon' to [lat, lon]"""
    if pd.isna(coord_str):
        return None
    try:
        parts = str(coord_str).strip().split(',')
        if len(parts) == 2:
            lat = float(parts[0].strip())
            lon = float(parts[1].strip())
            # Validate coordinates are reasonable for Indonesia
            if -15 <= lat <= 10 and 95 <= lon <= 145:
                return [lat, lon]
    except:
        pass
    return None

# Extract coordinates
df['coords'] = df['Koordinat'].apply(parse_coordinates)

# Filter out rows without valid coordinates
df_valid = df[df['coords'].notna()].copy()

print(f"Total rows: {len(df)}")
print(f"Rows with valid coordinates: {len(df_valid)}")

# Prepare marker data - separate SPBU and SPBUN
markers_data = []
spbu_count = 0
spbun_count = 0

for idx, row in df_valid.iterrows():
    # Get classification (SPBU or SPBUN)
    classification = str(row['SPBU/SPBUN']).strip() if pd.notna(row.get('SPBU/SPBUN', None)) else 'SPBUN'
    
    marker_info = {
        'lat': row['coords'][0],
        'lon': row['coords'][1],
        'no': row.get('No  Lembaga Penyalur', '') if pd.notna(row.get('No  Lembaga Penyalur', None)) else '',
        'mor': str(int(float(row.get('MOR', '')))) if pd.notna(row.get('MOR', None)) and str(row.get('MOR', '')).strip() and str(row.get('MOR', '')).replace('.', '').replace('-', '').isdigit() else (str(row.get('MOR', '')) if pd.notna(row.get('MOR', None)) else ''),
        'classification': classification,
        'kawasan': row.get('Kawasan', '') if pd.notna(row.get('Kawasan', None)) else '',
        'provinsi': row.get('Provinsi', '') if pd.notna(row.get('Provinsi', None)) else '',
        'kabupaten': row.get('Kabupaten/Kota', '') if pd.notna(row.get('Kabupaten/Kota', None)) else '',
        'kecamatan': row.get('Kecamatan', '') if pd.notna(row.get('Kecamatan', None)) else '',
        'nama_badan_usaha': row.get('Nama Badan Usaha', '') if pd.notna(row.get('Nama Badan Usaha', None)) else '',
        'badan_usaha': row.get('Badan Usaha', '') if pd.notna(row.get('Badan Usaha', None)) else '',
        'tipe_spbun': row.get('Tipe SPBUN', '') if pd.notna(row.get('Tipe SPBUN', None)) else '',
        'jenis_kepemilikan': row.get('Jenis Kepemilikan SPBUN', '') if pd.notna(row.get('Jenis Kepemilikan SPBUN', None)) else '',
        'alamat': row.get('Alamat', '') if pd.notna(row.get('Alamat', None)) else '',
        'pelabuhan': row.get('Pelabuhan (Pelabuhan & Non Pelabuhan)', '') if pd.notna(row.get('Pelabuhan (Pelabuhan & Non Pelabuhan)', None)) else '',
        'laut_sungai': row.get('Laut/Sungai', '') if pd.notna(row.get('Laut/Sungai', None)) else '',
        'spbu_sekitar': row.get('Keberadaan SPBU Sekitar (Km)', '') if pd.notna(row.get('Keberadaan SPBU Sekitar (Km)', None)) else ''
    }
    markers_data.append(marker_info)
    
    if classification == 'SPBU':
        spbu_count += 1
    else:
        spbun_count += 1

print(f"SPBU locations: {spbu_count}")
print(f"SPBUN locations: {spbun_count}")

# Get unique values for filters
tipe_spbun_values = sorted([str(v).strip() for v in df_valid['Tipe SPBUN'].dropna().unique() if str(v).strip()])
# Convert MOR to integers for display, but keep original for filtering
mor_values_raw = df_valid['MOR'].dropna().unique()
mor_values = sorted([str(int(float(v))) if pd.notna(v) and str(v).strip() else '' for v in mor_values_raw if str(v).strip()])
provinsi_values = sorted([str(v).strip() for v in df_valid['Provinsi'].dropna().unique() if str(v).strip()])
kawasan_values = sorted([str(v).strip() for v in df_valid['Kawasan'].dropna().unique() if str(v).strip()])

print(f"\nUnique Tipe SPBUN: {tipe_spbun_values}")
print(f"Unique MOR: {mor_values}")
print(f"Unique Provinsi: {provinsi_values}")
print(f"Unique Kawasan: {kawasan_values}")

# Calculate center point (average of all coordinates)
if markers_data:
    avg_lat = sum(m['lat'] for m in markers_data) / len(markers_data)
    avg_lon = sum(m['lon'] for m in markers_data) / len(markers_data)
else:
    avg_lat, avg_lon = -2.5489, 118.0149  # Default center of Indonesia

# Read Indonesia GeoJSON
geojson_path = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/id.json"
with open(geojson_path, 'r', encoding='utf-8') as f:
    indonesia_geojson = json.load(f)

# Create HTML file
html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SPBU/SPBUN Map with Filters</title>
    
    <!-- Leaflet CSS -->
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
          integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
          crossorigin=""/>
    
    <!-- Leaflet JS -->
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
            integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
            crossorigin=""></script>
    
    <!-- html2canvas for PNG export -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    
    <!-- SheetJS for Excel export -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script>
    
    <style>
        body {{
            margin: 0;
            padding: 0;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }}
        
        #map {{
            width: 100%;
            height: 100vh;
        }}
        
        #table-view {{
            width: 100%;
            height: 100vh;
            display: none;
            padding: 20px;
            overflow: auto;
        }}
        
        .table-container {{
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            overflow: auto;
        }}
        
        table {{
            width: 100%;
            border-collapse: collapse;
        }}
        
        th, td {{
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }}
        
        th {{
            background-color: #3498db;
            color: white;
            position: sticky;
            top: 0;
            z-index: 10;
        }}
        
        tr:hover {{
            background-color: #f5f5f5;
        }}
        
        .toolbar {{
            position: fixed;
            top: 10px;
            left: 10px;
            z-index: 2000;
            display: flex;
            gap: 10px;
            flex-direction: column;
        }}
        
        .toolbar button {{
            padding: 10px 15px;
            background: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            cursor: pointer;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
            font-size: 14px;
            font-weight: 500;
        }}
        
        .toolbar button:hover {{
            background: #f8f9fa;
        }}
        
        .sidebar {{
            position: fixed;
            top: 0;
            right: -450px;
            width: 450px;
            height: 100vh;
            background: white;
            box-shadow: -2px 0 10px rgba(0,0,0,0.3);
            transition: right 0.3s ease;
            z-index: 1500;
            overflow-y: auto;
            overflow-x: hidden;
            padding: 20px;
            padding-bottom: 60px;
            font-size: 13px;
            visibility: hidden;
            pointer-events: none;
            box-sizing: border-box;
        }}
        
        .sidebar.open {{
            right: 0;
            visibility: visible;
            pointer-events: auto;
        }}
        
        .sidebar-toggle {{
            position: fixed;
            top: 10px;
            right: 10px;
            z-index: 1600;
            padding: 10px 15px;
            background: #3498db;
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
            font-size: 16px;
        }}
        
        .sidebar-toggle:hover {{
            background: #2980b9;
        }}
        
        .filter-controls {{
            margin-top: 15px;
            padding-top: 15px;
            border-top: 1px solid #ddd;
        }}
        
        .filter-controls label {{
            display: flex;
            align-items: center;
            margin: 8px 0;
            cursor: pointer;
        }}
        
        .filter-controls input[type="checkbox"] {{
            margin-right: 8px;
            cursor: pointer;
        }}
        
        .filter-group {{
            max-height: 200px;
            overflow-y: auto;
            border: 1px solid #eee;
            padding: 8px;
            border-radius: 4px;
            margin-top: 5px;
        }}
        
        .legend {{
            margin-top: 15px;
            padding-top: 15px;
            border-top: 1px solid #ddd;
        }}
        
        .legend-item {{
            display: flex;
            align-items: center;
            margin: 5px 0;
        }}
        
        .legend-color {{
            width: 16px;
            height: 16px;
            border-radius: 50%;
            border: 2px solid white;
            box-shadow: 0 2px 5px rgba(0,0,0,0.3);
            margin-right: 8px;
        }}
        
        .custom-popup {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }}
        
        .custom-popup h4 {{
            margin-top: 0;
            color: #2c3e50;
            border-bottom: 2px solid #3498db;
            padding-bottom: 5px;
        }}
        
        .custom-popup .detail-row {{
            margin: 8px 0;
            padding: 5px;
            background: #f8f9fa;
            border-left: 3px solid #3498db;
            padding-left: 10px;
        }}
        
        .custom-popup .label {{
            font-weight: bold;
            color: #555;
        }}
        
        .custom-popup .value {{
            color: #333;
        }}
        
        .download-menu {{
            position: relative;
        }}
        
        .download-menu-btn {{
            padding: 10px 15px;
            background: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            cursor: pointer;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
            font-size: 14px;
            font-weight: 500;
            display: flex;
            align-items: center;
            gap: 8px;
        }}
        
        .download-menu-btn:hover {{
            background: #f8f9fa;
        }}
        
        .download-menu-btn::before {{
            content: '☰';
            font-size: 18px;
        }}
        
        .download-dropdown {{
            position: absolute;
            top: 100%;
            left: 0;
            margin-top: 5px;
            background: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            box-shadow: 0 4px 10px rgba(0,0,0,0.2);
            min-width: 150px;
            z-index: 2100;
            display: none;
        }}
        
        .download-dropdown.show {{
            display: block;
        }}
        
        .download-dropdown button {{
            display: block;
            width: 100%;
            padding: 10px 15px;
            background: white;
            border: none;
            text-align: left;
            cursor: pointer;
            font-size: 13px;
        }}
        
        .download-dropdown button:hover {{
            background: #f8f9fa;
        }}
        
        .download-dropdown button:first-child {{
            border-top-left-radius: 5px;
            border-top-right-radius: 5px;
        }}
        
        .download-dropdown button:last-child {{
            border-bottom-left-radius: 5px;
            border-bottom-right-radius: 5px;
        }}
        
        .download-option {{
            display: none;
        }}
        
        .download-option.show {{
            display: block !important;
        }}
        
        /* Leaflet layer control styling */
        .leaflet-control-layers {{
            background: white;
            border-radius: 5px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
            z-index: 1700 !important;
        }}
        
        .leaflet-top.leaflet-right {{
            z-index: 1700 !important;
        }}
        
        .leaflet-control-layers-toggle {{
            background-image: url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTEyIDJMMTMuMDkgOC4yNkwyMCA5TDEzLjA5IDE1Ljc0TDEyIDIyTDEwLjkxIDE1Ljc0TDQgOUwxMC45MSA4LjI2TDEyIDJaIiBmaWxsPSIjMzMzIi8+Cjwvc3ZnPgo=');
            background-size: 20px 20px;
            background-repeat: no-repeat;
            background-position: center;
        }}
        
        .radius-filter-controls {{
            margin-top: 15px;
            padding-top: 15px;
            border-top: 1px solid #ddd;
        }}
        
        .radius-buttons {{
            display: flex;
            flex-wrap: wrap;
            gap: 5px;
            margin-top: 8px;
        }}
        
        .radius-btn {{
            padding: 6px 12px;
            background: #f8f9fa;
            border: 1px solid #ddd;
            border-radius: 4px;
            cursor: pointer;
            font-size: 12px;
            transition: all 0.2s;
        }}
        
        .radius-btn:hover {{
            background: #e9ecef;
        }}
        
        .radius-btn.active {{
            background: #3498db;
            color: white;
            border-color: #3498db;
        }}
        
        .radius-input-group {{
            display: flex;
            gap: 5px;
            margin-top: 8px;
            align-items: center;
        }}
        
        .radius-input-group input {{
            flex: 1;
            padding: 6px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 12px;
        }}
        
        .radius-input-group button {{
            padding: 6px 12px;
            background: #3498db;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 12px;
        }}
        
        .radius-input-group button:hover {{
            background: #2980b9;
        }}
        
        .radius-mode-btn {{
            width: 100%;
            padding: 8px;
            margin-top: 8px;
            background: #27ae60;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 13px;
            font-weight: 500;
        }}
        
        .radius-mode-btn:hover {{
            background: #229954;
        }}
        
        .radius-mode-btn.active {{
            background: #e74c3c;
        }}
        
        .radius-mode-btn.active:hover {{
            background: #c0392b;
        }}
        
        .radius-info {{
            margin-top: 8px;
            padding: 8px;
            background: #f8f9fa;
            border-radius: 4px;
            font-size: 12px;
            color: #555;
        }}
        
        .radius-info strong {{
            color: #2c3e50;
        }}
        
        .color-toggle {{
            display: flex;
            align-items: center;
            margin-bottom: 8px;
            padding: 5px;
            background: #f8f9fa;
            border-radius: 4px;
        }}
        
        .color-toggle label {{
            display: flex;
            align-items: center;
            cursor: pointer;
            margin: 0;
            flex: 1;
        }}
        
        .color-toggle input[type="checkbox"] {{
            margin-right: 8px;
            cursor: pointer;
        }}
        
        .color-legend {{
            margin-top: 8px;
            padding: 8px;
            background: #f8f9fa;
            border-radius: 4px;
            font-size: 11px;
            max-height: 150px;
            overflow-y: auto;
            display: none;
        }}
        
        .color-legend.show {{
            display: block;
        }}
        
        .color-legend-item {{
            display: flex;
            align-items: center;
            margin: 3px 0;
        }}
        
        .color-legend-color {{
            width: 12px;
            height: 12px;
            border-radius: 50%;
            border: 1px solid white;
            box-shadow: 0 1px 3px rgba(0,0,0,0.3);
            margin-right: 6px;
        }}
    </style>
</head>
<body>
    <div class="toolbar">
        <button onclick="toggleView()">Switch to Table</button>
        <div class="download-menu">
            <button class="download-menu-btn" onclick="toggleDownloadMenu()">Download</button>
            <div class="download-dropdown" id="download-dropdown">
                <button onclick="downloadPNG()" id="download-png-option" class="download-option">Download PNG</button>
                <button onclick="downloadCSV()" id="download-csv-option" class="download-option">Download CSV</button>
                <button onclick="downloadGeoJSON()" id="download-geojson-option" class="download-option">Download GeoJSON</button>
                <button onclick="downloadExcel()" id="download-excel-option" class="download-option">Download Excel</button>
            </div>
        </div>
    </div>
    
    <button class="sidebar-toggle" onclick="toggleSidebar()">☰ Options</button>
    
    <div id="map"></div>
    <div id="table-view">
        <div class="table-container">
            <table id="data-table">
                <thead id="table-head"></thead>
                <tbody id="table-body"></tbody>
            </table>
        </div>
    </div>
    
    <div class="sidebar" id="sidebar">
        <h3>SPBU/SPBUN Map</h3>
        <p><strong>Total Locations:</strong> {len(markers_data)}</p>
        <p><strong>SPBU:</strong> {spbu_count} | <strong>SPBUN:</strong> {spbun_count}</p>
        
        <div class="legend">
            <strong>Legend:</strong>
            <div class="legend-item">
                <div class="legend-color" style="background-color: #e74c3c;"></div>
                <span>SPBU</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background-color: #3498db;"></div>
                <span>SPBUN</span>
            </div>
        </div>
        
        <div class="filter-controls">
            <strong>Filter by Type:</strong>
            <label>
                <input type="checkbox" id="filter-spbu">
                Show SPBU ({spbu_count})
            </label>
            <label>
                <input type="checkbox" id="filter-spbun" checked>
                Show SPBUN ({spbun_count})
            </label>
        </div>
        
        <div class="filter-controls">
            <strong>Filter by Tipe SPBUN:</strong>
            <div class="color-toggle">
                <label>
                    <input type="checkbox" id="color-toggle-tipe">
                    <span>Color by Tipe SPBUN</span>
                </label>
            </div>
            <div class="color-legend" id="color-legend-tipe"></div>
            <div class="filter-group">
                <label>
                    <input type="checkbox" id="tipe-all" checked>
                    <strong>Select All</strong>
                </label>
                {''.join([f'<label><input type="checkbox" class="tipe-filter" value="{v}" checked>{v}</label>' for v in tipe_spbun_values])}
            </div>
        </div>
        
        <div class="filter-controls">
            <strong>Filter by MOR:</strong>
            <div class="color-toggle">
                <label>
                    <input type="checkbox" id="color-toggle-mor">
                    <span>Color by MOR</span>
                </label>
            </div>
            <div class="color-legend" id="color-legend-mor"></div>
            <div class="filter-group">
                <label>
                    <input type="checkbox" id="mor-all" checked>
                    <strong>Select All</strong>
                </label>
                {''.join([f'<label><input type="checkbox" class="mor-filter" value="{v}" checked>{v}</label>' for v in mor_values])}
            </div>
        </div>
        
        <div class="filter-controls">
            <strong>Filter by Provinsi:</strong>
            <div class="color-toggle">
                <label>
                    <input type="checkbox" id="color-toggle-provinsi">
                    <span>Color by Provinsi</span>
                </label>
            </div>
            <div class="color-legend" id="color-legend-provinsi"></div>
            <div class="filter-group">
                <label>
                    <input type="checkbox" id="provinsi-all" checked>
                    <strong>Select All</strong>
                </label>
                {''.join([f'<label><input type="checkbox" class="provinsi-filter" value="{v}" checked>{v}</label>' for v in provinsi_values])}
            </div>
        </div>
        
        <div class="filter-controls">
            <strong>Filter by Kawasan:</strong>
            <div class="color-toggle">
                <label>
                    <input type="checkbox" id="color-toggle-kawasan">
                    <span>Color by Kawasan</span>
                </label>
            </div>
            <div class="color-legend" id="color-legend-kawasan"></div>
            <div class="filter-group">
                <label>
                    <input type="checkbox" id="kawasan-all" checked>
                    <strong>Select All</strong>
                </label>
                {''.join([f'<label><input type="checkbox" class="kawasan-filter" value="{v}" checked>{v}</label>' for v in kawasan_values])}
            </div>
        </div>
        
        <div class="radius-filter-controls">
            <strong>Filter SPBU by Radius:</strong>
            <button class="radius-mode-btn" id="radius-mode-btn" onclick="toggleRadiusMode()">Enable Radius Filter</button>
            <div id="radius-controls" style="display: none;">
                <div style="margin-top: 10px; margin-bottom: 10px;">
                    <strong style="font-size: 12px;">Filter Mode:</strong>
                    <div style="display: flex; gap: 10px; margin-top: 5px;">
                        <label style="display: flex; align-items: center; cursor: pointer;">
                            <input type="radio" name="radius-mode" id="radius-mode-single" value="single" checked style="margin-right: 5px;">
                            <span style="font-size: 12px;">Single Point</span>
                        </label>
                        <label style="display: flex; align-items: center; cursor: pointer;">
                            <input type="radio" name="radius-mode" id="radius-mode-all-spbun" value="all-spbun" style="margin-right: 5px;">
                            <span style="font-size: 12px;">All SPBUN</span>
                        </label>
                    </div>
                </div>
                <p id="radius-instructions" style="font-size: 11px; color: #666; margin-top: 8px; margin-bottom: 8px;">
                    Click on map or an SPBUN marker to set reference point
                </p>
                <div class="radius-buttons">
                    <button class="radius-btn" onclick="setRadius(5)">5 km</button>
                    <button class="radius-btn" onclick="setRadius(10)">10 km</button>
                    <button class="radius-btn" onclick="setRadius(20)">20 km</button>
                    <button class="radius-btn" onclick="setRadius(30)">30 km</button>
                </div>
                <div class="radius-input-group">
                    <input type="number" id="custom-radius" placeholder="Custom (km)" min="0" step="0.1">
                    <button onclick="setCustomRadius()">Apply</button>
                </div>
                <div class="radius-info" id="radius-info" style="display: none;">
                    <div id="radius-info-single">
                        <strong>Reference Point:</strong> <span id="radius-ref-point">Not set</span><br/>
                        <strong>Radius:</strong> <span id="radius-value">-</span> km<br/>
                        <strong>SPBU Found:</strong> <span id="radius-count">0</span>
                    </div>
                    <div id="radius-info-all-spbun" style="display: none;">
                        <strong>Mode:</strong> All SPBUN<br/>
                        <strong>Radius:</strong> <span id="radius-value-all">-</span> km<br/>
                        <strong>SPBUN Count:</strong> <span id="spbun-count">0</span><br/>
                        <strong>SPBU Found:</strong> <span id="radius-count-all">0</span>
                    </div>
                </div>
            </div>
        </div>
        
        <p style="margin-top: 15px; margin-bottom: 20px; font-size: 12px; color: #999;">
            <strong>Hover</strong> over markers to see details<br/>
            <strong>Click</strong> markers for more information
        </p>
    </div>
    
    <script>
        // Global variables
        var currentView = 'map';
        var markersData = {json.dumps(markers_data, ensure_ascii=False)};
        var filteredMarkersData = markersData;
        var radiusModeActive = false;
        var radiusModeType = 'single'; // 'single' or 'all-spbun'
        var radiusReferencePoint = null;
        var currentRadius = null;
        var radiusCircle = null;
        var radiusMarker = null;
        var allSpbunCircles = []; // Store circles for all SPBUN mode
        var updateMarkerVisibility = null; // Will be assigned in map initialization
        var map = null; // Will be assigned in map initialization
        var allMarkers = []; // Will be populated in map initialization
        var spbuMarkers = []; // Will be populated in map initialization
        var spbunMarkers = []; // Will be populated in map initialization
        var activeColorMode = null; // 'tipe', 'mor', 'provinsi', 'kawasan', or null
        var colorMaps = {{}}; // Store color mappings for each filter type
        
        function toggleView() {{
            if (currentView === 'map') {{
                currentView = 'table';
                document.getElementById('map').style.display = 'none';
                document.getElementById('table-view').style.display = 'block';
                document.querySelector('.toolbar button').textContent = 'Switch to Map';
                renderTable();
            }} else {{
                currentView = 'map';
                document.getElementById('map').style.display = 'block';
                document.getElementById('table-view').style.display = 'none';
                document.querySelector('.toolbar button').textContent = 'Switch to Table';
            }}
            updateDownloadMenu();
        }}
        
        // Initialize download menu
        updateDownloadMenu();
        
        function toggleSidebar() {{
            document.getElementById('sidebar').classList.toggle('open');
        }}
        
        function toggleDownloadMenu() {{
            var dropdown = document.getElementById('download-dropdown');
            dropdown.classList.toggle('show');
        }}
        
        function updateDownloadMenu() {{
            var pngOption = document.getElementById('download-png-option');
            var csvOption = document.getElementById('download-csv-option');
            var geojsonOption = document.getElementById('download-geojson-option');
            var excelOption = document.getElementById('download-excel-option');
            
            // Remove all show classes first
            pngOption.classList.remove('show');
            csvOption.classList.remove('show');
            geojsonOption.classList.remove('show');
            excelOption.classList.remove('show');
            
            if (currentView === 'map') {{
                pngOption.classList.add('show');
            }} else {{
                csvOption.classList.add('show');
                geojsonOption.classList.add('show');
                excelOption.classList.add('show');
            }}
        }}
        
        // Close download menu when clicking outside
        document.addEventListener('click', function(event) {{
            var downloadMenu = document.querySelector('.download-menu');
            var dropdown = document.getElementById('download-dropdown');
            if (downloadMenu && !downloadMenu.contains(event.target)) {{
                dropdown.classList.remove('show');
            }}
        }});
        
        function renderTable() {{
            var thead = document.getElementById('table-head');
            var tbody = document.getElementById('table-body');
            
            // Clear existing content
            thead.innerHTML = '';
            tbody.innerHTML = '';
            
            if (filteredMarkersData.length === 0) {{
                tbody.innerHTML = '<tr><td colspan="17" style="text-align: center;">No data to display</td></tr>';
                return;
            }}
            
            // Create header
            var headerRow = document.createElement('tr');
            var headers = ['No', 'Classification', 'MOR', 'Kawasan', 'Provinsi', 'Kabupaten/Kota', 'Kecamatan', 
                          'Nama Badan Usaha', 'Badan Usaha', 'Tipe SPBUN', 'Jenis Kepemilikan', 
                          'Alamat', 'Pelabuhan', 'Laut/Sungai', 'SPBU Sekitar', 'Latitude', 'Longitude'];
            headers.forEach(function(header) {{
                var th = document.createElement('th');
                th.textContent = header;
                headerRow.appendChild(th);
            }});
            thead.appendChild(headerRow);
            
            // Create rows
            filteredMarkersData.forEach(function(data) {{
                var row = document.createElement('tr');
                var values = [
                    data.no || '',
                    data.classification || '',
                    data.mor || '',
                    data.kawasan || '',
                    data.provinsi || '',
                    data.kabupaten || '',
                    data.kecamatan || '',
                    data.nama_badan_usaha || '',
                    data.badan_usaha || '',
                    data.tipe_spbun || '',
                    data.jenis_kepemilikan || '',
                    data.alamat || '',
                    data.pelabuhan || '',
                    data.laut_sungai || '',
                    data.spbu_sekitar || '',
                    data.lat || '',
                    data.lon || ''
                ];
                values.forEach(function(value) {{
                    var td = document.createElement('td');
                    td.textContent = value;
                    row.appendChild(td);
                }});
                tbody.appendChild(row);
            }});
        }}
        
        function downloadPNG() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            if (currentView !== 'map') {{
                alert('Please switch to map view to download PNG');
                return;
            }}
            
            // Hide UI elements before capturing
            var toolbar = document.querySelector('.toolbar');
            var sidebar = document.getElementById('sidebar');
            var sidebarToggle = document.querySelector('.sidebar-toggle');
            var downloadDropdown = document.getElementById('download-dropdown');
            
            var toolbarDisplay = toolbar ? toolbar.style.display : '';
            var sidebarVisibility = sidebar ? sidebar.style.visibility : '';
            var sidebarToggleDisplay = sidebarToggle ? sidebarToggle.style.display : '';
            
            if (toolbar) toolbar.style.display = 'none';
            if (sidebar) sidebar.style.visibility = 'hidden';
            if (sidebarToggle) sidebarToggle.style.display = 'none';
            if (downloadDropdown) downloadDropdown.classList.remove('show');
            
            // Wait a bit for UI to hide
            setTimeout(function() {{
                html2canvas(document.getElementById('map'), {{
                    useCORS: true,
                    logging: false,
                    width: document.getElementById('map').offsetWidth,
                    height: document.getElementById('map').offsetHeight,
                    ignoreElements: function(element) {{
                        return element.classList.contains('toolbar') || 
                               element.classList.contains('sidebar') || 
                               element.classList.contains('sidebar-toggle') ||
                               element.classList.contains('download-menu') ||
                               element.classList.contains('download-dropdown') ||
                               element.classList.contains('leaflet-control-layers');
                    }}
                }}).then(function(canvas) {{
                    // Restore UI elements
                    if (toolbar) toolbar.style.display = toolbarDisplay || '';
                    if (sidebar) sidebar.style.visibility = sidebarVisibility || '';
                    if (sidebarToggle) sidebarToggle.style.display = sidebarToggleDisplay || '';
                    
                    var link = document.createElement('a');
                    link.download = 'spbu_map.png';
                    link.href = canvas.toDataURL('image/png');
                    link.click();
                }});
            }}, 100);
        }}
        
        function downloadCSV() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            var csv = 'No,Classification,MOR,Kawasan,Provinsi,Kabupaten/Kota,Kecamatan,Nama Badan Usaha,Badan Usaha,Tipe SPBUN,Jenis Kepemilikan,Alamat,Pelabuhan,Laut/Sungai,SPBU Sekitar,Latitude,Longitude\\n';
            
            filteredMarkersData.forEach(function(data) {{
                csv += [
                    data.no || '',
                    data.classification || '',
                    data.mor || '',
                    '"' + (data.kawasan || '').replace(/"/g, '""') + '"',
                    '"' + (data.provinsi || '').replace(/"/g, '""') + '"',
                    '"' + (data.kabupaten || '').replace(/"/g, '""') + '"',
                    '"' + (data.kecamatan || '').replace(/"/g, '""') + '"',
                    '"' + (data.nama_badan_usaha || '').replace(/"/g, '""') + '"',
                    '"' + (data.badan_usaha || '').replace(/"/g, '""') + '"',
                    '"' + (data.tipe_spbun || '').replace(/"/g, '""') + '"',
                    '"' + (data.jenis_kepemilikan || '').replace(/"/g, '""') + '"',
                    '"' + (data.alamat || '').replace(/"/g, '""') + '"',
                    '"' + (data.pelabuhan || '').replace(/"/g, '""') + '"',
                    '"' + (data.laut_sungai || '').replace(/"/g, '""') + '"',
                    data.spbu_sekitar || '',
                    data.lat || '',
                    data.lon || ''
                ].join(',') + '\\n';
            }});
            
            var blob = new Blob([csv], {{ type: 'text/csv;charset=utf-8;' }});
            var link = document.createElement('a');
            link.href = URL.createObjectURL(blob);
            link.download = 'spbu_data.csv';
            link.click();
        }}
        
        function downloadGeoJSON() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            var geojson = {{
                type: 'FeatureCollection',
                features: filteredMarkersData.map(function(data) {{
                    return {{
                        type: 'Feature',
                        geometry: {{
                            type: 'Point',
                            coordinates: [data.lon, data.lat]
                        }},
                        properties: {{
                            no: data.no,
                            classification: data.classification,
                            mor: data.mor,
                            kawasan: data.kawasan,
                            provinsi: data.provinsi,
                            kabupaten: data.kabupaten,
                            kecamatan: data.kecamatan,
                            nama_badan_usaha: data.nama_badan_usaha,
                            badan_usaha: data.badan_usaha,
                            tipe_spbun: data.tipe_spbun,
                            jenis_kepemilikan: data.jenis_kepemilikan,
                            alamat: data.alamat,
                            pelabuhan: data.pelabuhan,
                            laut_sungai: data.laut_sungai,
                            spbu_sekitar: data.spbu_sekitar
                        }}
                    }};
                }})
            }};
            
            var blob = new Blob([JSON.stringify(geojson, null, 2)], {{ type: 'application/json' }});
            var link = document.createElement('a');
            link.href = URL.createObjectURL(blob);
            link.download = 'spbu_data.geojson';
            link.click();
        }}
        
        function downloadExcel() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            var ws_data = [];
            
            // Header row
            ws_data.push(['No', 'Classification', 'MOR', 'Kawasan', 'Provinsi', 'Kabupaten/Kota', 'Kecamatan', 
                         'Nama Badan Usaha', 'Badan Usaha', 'Tipe SPBUN', 'Jenis Kepemilikan', 
                         'Alamat', 'Pelabuhan', 'Laut/Sungai', 'SPBU Sekitar', 'Latitude', 'Longitude']);
            
            // Data rows
            filteredMarkersData.forEach(function(data) {{
                ws_data.push([
                    data.no || '',
                    data.classification || '',
                    data.mor || '',
                    data.kawasan || '',
                    data.provinsi || '',
                    data.kabupaten || '',
                    data.kecamatan || '',
                    data.nama_badan_usaha || '',
                    data.badan_usaha || '',
                    data.tipe_spbun || '',
                    data.jenis_kepemilikan || '',
                    data.alamat || '',
                    data.pelabuhan || '',
                    data.laut_sungai || '',
                    data.spbu_sekitar || '',
                    data.lat || '',
                    data.lon || ''
                ]);
            }});
            
            var wb = XLSX.utils.book_new();
            var ws = XLSX.utils.aoa_to_sheet(ws_data);
            XLSX.utils.book_append_sheet(wb, ws, 'SPBU Data');
            XLSX.writeFile(wb, 'spbu_data.xlsx');
        }}
        
        // Update filtered data when filters change
        function updateFilteredData() {{
            var showSPBU = document.getElementById('filter-spbu').checked;
            var showSPBUN = document.getElementById('filter-spbun').checked;
            
            // Get selected filter values
            var selectedTipe = Array.from(document.querySelectorAll('.tipe-filter:checked')).map(cb => cb.value);
            var selectedMOR = Array.from(document.querySelectorAll('.mor-filter:checked')).map(cb => cb.value);
            var selectedProvinsi = Array.from(document.querySelectorAll('.provinsi-filter:checked')).map(cb => cb.value);
            var selectedKawasan = Array.from(document.querySelectorAll('.kawasan-filter:checked')).map(cb => cb.value);
            
            filteredMarkersData = markersData.filter(function(data) {{
                var isSPBU = data.classification === 'SPBU';
                var isSPBUN = data.classification === 'SPBUN';
                
                // Determine if SPBU should be considered based on checkbox or radius filter
                var isSPBUFromCheckbox = false; // Track if SPBU is shown via checkbox
                if (isSPBU) {{
                    // If SPBU checkbox is checked, show all SPBU (ignore radius filter and other filters)
                    if (showSPBU) {{
                        isSPBUFromCheckbox = true;
                        // Skip all other filters - show all SPBU
                    }} else if (radiusModeActive && currentRadius !== null) {{
                        // Only use radius filter if checkbox is not checked
                        var passesRadius = false;
                        var isRadiusFilteredSPBU = false;
                        
                        if (radiusModeType === 'single') {{
                            if (radiusReferencePoint) {{
                                var distance = calculateDistance(
                                    radiusReferencePoint.lat,
                                    radiusReferencePoint.lon,
                                    data.lat,
                                    data.lon
                                );
                                if (distance <= currentRadius) {{
                                    passesRadius = true;
                                    isRadiusFilteredSPBU = true;
                                }}
                            }}
                        }} else {{
                            // All SPBUN mode - check against every SPBUN that passes filters
                            markersData.forEach(function(spbunData) {{
                                if (spbunData.classification === 'SPBUN') {{
                                    var spbunPasses = true;
                                    if (selectedTipe.length > 0 && !selectedTipe.includes(spbunData.tipe_spbun)) spbunPasses = false;
                                    if (spbunPasses && selectedMOR.length > 0) {{
                                        var morStrSPBUN = String(spbunData.mor || '').trim();
                                        var morIntSPBUN = morStrSPBUN;
                                        if (morStrSPBUN && !isNaN(parseFloat(morStrSPBUN))) {{
                                            morIntSPBUN = String(parseInt(parseFloat(morStrSPBUN)));
                                        }}
                                        if (!selectedMOR.includes(morStrSPBUN) && !selectedMOR.includes(morIntSPBUN)) spbunPasses = false;
                                    }}
                                    if (spbunPasses && selectedProvinsi.length > 0 && !selectedProvinsi.includes(spbunData.provinsi)) spbunPasses = false;
                                    if (spbunPasses && selectedKawasan.length > 0 && !selectedKawasan.includes(spbunData.kawasan)) spbunPasses = false;
                                    
                                    if (spbunPasses) {{
                                        var radiusDistance = calculateDistance(
                                            spbunData.lat,
                                            spbunData.lon,
                                            data.lat,
                                            data.lon
                                        );
                                        if (radiusDistance <= currentRadius) {{
                                            passesRadius = true;
                                            isRadiusFilteredSPBU = true;
                                        }}
                                    }}
                                }}
                            }});
                        }}
                        
                        if (!passesRadius) return false;
                        
                        // If SPBU is included via radius filter, skip other filters (MOR, Provinsi, Kawasan)
                        if (isRadiusFilteredSPBU) {{
                            return true;
                        }}
                    }} else {{
                        // No checkbox checked and no radius filter - hide SPBU
                        return false;
                    }}
                }} else if (isSPBUN) {{
                    if (!showSPBUN) return false;
                }}
                
                // If SPBU checkbox is checked, skip all filters and return true
                if (isSPBUFromCheckbox) {{
                    return true;
                }}
                
                // Filter by Tipe SPBUN (only applies to SPBUN)
                if (isSPBUN && selectedTipe.length > 0) {{
                    if (!selectedTipe.includes(data.tipe_spbun)) return false;
                }}
                
                // Filter by MOR (only apply to non-radius-filtered SPBU and SPBUN)
                if (selectedMOR.length > 0) {{
                    var morStr = String(data.mor || '').trim();
                    // Also try converting to int in case of float values
                    var morInt = morStr;
                    if (morStr && !isNaN(parseFloat(morStr))) {{
                        morInt = String(parseInt(parseFloat(morStr)));
                    }}
                    if (!selectedMOR.includes(morStr) && !selectedMOR.includes(morInt)) return false;
                }}
                
                // Filter by Provinsi (only apply to non-radius-filtered SPBU and SPBUN)
                if (selectedProvinsi.length > 0) {{
                    if (!selectedProvinsi.includes(data.provinsi)) return false;
                }}
                
                // Filter by Kawasan (only apply to non-radius-filtered SPBU and SPBUN)
                if (selectedKawasan.length > 0) {{
                    if (!selectedKawasan.includes(data.kawasan)) return false;
                }}
                
                return true;
            }});
            
            if (currentView === 'table') {{
                renderTable();
            }}
        }}
        
        // Setup select all functionality
        function setupSelectAll(groupId, filterClass) {{
            var selectAll = document.getElementById(groupId);
            var filters = document.querySelectorAll('.' + filterClass);
            
            if (selectAll && filters.length > 0) {{
                selectAll.addEventListener('change', function() {{
                    filters.forEach(function(cb) {{
                        cb.checked = this.checked;
                    }}, this);
                    updateFilteredData();
                    updateMarkerVisibility();
                }});
                
                filters.forEach(function(cb) {{
                    cb.addEventListener('change', function() {{
                        var allChecked = Array.from(filters).every(function(f) {{ return f.checked; }});
                        selectAll.checked = allChecked;
                        updateFilteredData();
                        updateMarkerVisibility();
                    }});
                }});
            }}
        }}
        
        // Haversine formula to calculate distance between two points in kilometers
        function calculateDistance(lat1, lon1, lat2, lon2) {{
            var R = 6371; // Earth's radius in kilometers
            var dLat = (lat2 - lat1) * Math.PI / 180;
            var dLon = (lon2 - lon1) * Math.PI / 180;
            var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                    Math.sin(dLon / 2) * Math.sin(dLon / 2);
            var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
            return R * c;
        }}
        
        // Generate distinct colors for values
        function generateColors(values) {{
            var colors = [];
            var hueStep = 360 / values.length;
            for (var i = 0; i < values.length; i++) {{
                var hue = (i * hueStep) % 360;
                var color = 'hsl(' + hue + ', 70%, 50%)';
                colors.push(color);
            }}
            return colors;
        }}
        
        // Create color mapping for a filter type
        function createColorMap(filterType, values) {{
            var colors = generateColors(values);
            var colorMap = {{}};
            values.forEach(function(value, index) {{
                colorMap[value] = colors[index];
            }});
            colorMaps[filterType] = colorMap;
            return colorMap;
        }}
        
        // Get color for a marker based on active color mode
        function getMarkerColor(data) {{
            if (!activeColorMode) {{
                // Default colors
                return data.classification === 'SPBU' ? '#e74c3c' : '#3498db';
            }}
            
            var value = '';
            if (activeColorMode === 'tipe') {{
                value = String(data.tipe_spbun || '').trim();
            }} else if (activeColorMode === 'mor') {{
                var morStr = String(data.mor || '').trim();
                if (morStr && !isNaN(parseFloat(morStr))) {{
                    value = String(parseInt(parseFloat(morStr)));
                }} else {{
                    value = morStr;
                }}
            }} else if (activeColorMode === 'provinsi') {{
                value = String(data.provinsi || '').trim();
            }} else if (activeColorMode === 'kawasan') {{
                value = String(data.kawasan || '').trim();
            }}
            
            var colorMap = colorMaps[activeColorMode];
            if (colorMap && colorMap[value]) {{
                return colorMap[value];
            }}
            
            // Fallback to default if value not found
            return data.classification === 'SPBU' ? '#e74c3c' : '#3498db';
        }}
        
        // Create icon with specific color
        function createColoredIcon(color, isSPBU) {{
            return L.divIcon({{
                className: isSPBU ? 'spbu-marker' : 'spbun-marker',
                html: '<div style="background-color: ' + color + '; width: 12px; height: 12px; border-radius: 50%; border: 2px solid white; box-shadow: 0 2px 5px rgba(0,0,0,0.3);"></div>',
                iconSize: [12, 12],
                iconAnchor: [6, 6]
            }});
        }}
        
        // Update all marker colors
        function updateMarkerColors() {{
            allMarkers.forEach(function(marker) {{
                var markerData = marker.options.data;
                var color = getMarkerColor(markerData);
                var isSPBU = markerData.classification === 'SPBU';
                var newIcon = createColoredIcon(color, isSPBU);
                marker.setIcon(newIcon);
            }});
        }}
        
        // Setup color toggle
        function setupColorToggle(toggleId, legendId, filterType, values) {{
            var toggle = document.getElementById(toggleId);
            var legend = document.getElementById(legendId);
            
            if (!toggle || !legend) return;
            
            // Create color map
            var colorMap = createColorMap(filterType, values);
            
            // Create legend HTML
            function updateLegend() {{
                var legendHTML = '';
                values.forEach(function(value) {{
                    var color = colorMap[value];
                    legendHTML += '<div class="color-legend-item">' +
                        '<div class="color-legend-color" style="background-color: ' + color + ';"></div>' +
                        '<span>' + value + '</span>' +
                        '</div>';
                }});
                legend.innerHTML = legendHTML;
            }}
            
            updateLegend();
            
            toggle.addEventListener('change', function() {{
                // Uncheck other toggles
                document.querySelectorAll('.color-toggle input[type="checkbox"]').forEach(function(cb) {{
                    if (cb.id !== toggleId) {{
                        cb.checked = false;
                        var otherLegendId = cb.id.replace('color-toggle-', 'color-legend-');
                        var otherLegend = document.getElementById(otherLegendId);
                        if (otherLegend) {{
                            otherLegend.classList.remove('show');
                        }}
                    }}
                }});
                
                if (this.checked) {{
                    activeColorMode = filterType;
                    legend.classList.add('show');
                    updateMarkerColors();
                }} else {{
                    activeColorMode = null;
                    legend.classList.remove('show');
                    updateMarkerColors();
                }}
            }});
        }}
        
        // Toggle radius filter mode
        function toggleRadiusMode() {{
            radiusModeActive = !radiusModeActive;
            var btn = document.getElementById('radius-mode-btn');
            var controls = document.getElementById('radius-controls');
            
            if (radiusModeActive) {{
                btn.textContent = 'Disable Radius Filter';
                btn.classList.add('active');
                controls.style.display = 'block';
                // Uncheck SPBU checkbox when enabling radius filter
                document.getElementById('filter-spbu').checked = false;
                updateRadiusModeUI();
                // Change cursor to crosshair when hovering over map (only for single mode)
                if (radiusModeType === 'single') {{
                    document.getElementById('map').style.cursor = 'crosshair';
                }} else {{
                    document.getElementById('map').style.cursor = '';
                }}
            }} else {{
                btn.textContent = 'Enable Radius Filter';
                btn.classList.remove('active');
                controls.style.display = 'none';
                document.getElementById('map').style.cursor = '';
                // Clear radius filter
                clearRadiusFilter();
            }}
            // Update marker visibility
            if (updateMarkerVisibility) {{
                updateMarkerVisibility();
            }}
        }}
        
        // Update UI based on radius mode type
        function updateRadiusModeUI() {{
            var singleMode = document.getElementById('radius-mode-single');
            var allSpbunMode = document.getElementById('radius-mode-all-spbun');
            var instructions = document.getElementById('radius-instructions');
            var infoSingle = document.getElementById('radius-info-single');
            var infoAllSpbun = document.getElementById('radius-info-all-spbun');
            
            if (singleMode.checked) {{
                radiusModeType = 'single';
                instructions.textContent = 'Click on map or an SPBUN marker to set reference point';
                if (infoSingle) infoSingle.style.display = 'block';
                if (infoAllSpbun) infoAllSpbun.style.display = 'none';
                document.getElementById('map').style.cursor = 'crosshair';
            }} else {{
                radiusModeType = 'all-spbun';
                instructions.textContent = 'Shows SPBU within radius of all SPBUN locations';
                if (infoSingle) infoSingle.style.display = 'none';
                if (infoAllSpbun) infoAllSpbun.style.display = 'block';
                document.getElementById('map').style.cursor = '';
            }}
            
            // If radius is already set, reapply filter
            if (currentRadius !== null) {{
                if (radiusModeType === 'all-spbun') {{
                    applyRadiusFilter();
                }} else if (radiusReferencePoint) {{
                    applyRadiusFilter();
                }}
            }}
        }}
        
        // Set reference point from map click or marker
        function setReferencePoint(lat, lon, markerData) {{
            if (!radiusModeActive || !map) return;
            
            radiusReferencePoint = {{ lat: lat, lon: lon, data: markerData }};
            
            // Update info display
            var refPointText = lat.toFixed(4) + ', ' + lon.toFixed(4);
            if (markerData && markerData.no) {{
                refPointText = markerData.classification + ' #' + markerData.no + ' (' + refPointText + ')';
            }}
            document.getElementById('radius-ref-point').textContent = refPointText;
            document.getElementById('radius-info').style.display = 'block';
            
            // Add/update marker for reference point
            if (radiusMarker) {{
                map.removeLayer(radiusMarker);
            }}
            radiusMarker = L.marker([lat, lon], {{
                icon: L.divIcon({{
                    className: 'radius-ref-marker',
                    html: '<div style="background-color: #f39c12; width: 16px; height: 16px; border-radius: 50%; border: 3px solid white; box-shadow: 0 2px 8px rgba(0,0,0,0.5);"></div>',
                    iconSize: [16, 16],
                    iconAnchor: [8, 8]
                }})
            }}).addTo(map);
            
            // If radius is already set, apply filter
            if (currentRadius !== null) {{
                applyRadiusFilter();
            }}
        }}
        
        // Set radius value
        function setRadius(km) {{
            currentRadius = km;
            document.getElementById('radius-value').textContent = km;
            document.getElementById('radius-value-all').textContent = km;
            document.getElementById('custom-radius').value = km;
            
            // Update active button
            document.querySelectorAll('.radius-btn').forEach(function(btn) {{
                btn.classList.remove('active');
                if (btn.textContent.trim() === km + ' km') {{
                    btn.classList.add('active');
                }}
            }});
            
            if (radiusModeType === 'all-spbun') {{
                // All SPBUN mode - apply immediately
                applyRadiusFilter();
            }} else {{
                // Single point mode - need reference point
                if (radiusReferencePoint) {{
                    applyRadiusFilter();
                }} else {{
                    alert('Please click on the map or an SPBUN marker to set a reference point first.');
                }}
            }}
        }}
        
        // Set custom radius
        function setCustomRadius() {{
            var customValue = parseFloat(document.getElementById('custom-radius').value);
            if (isNaN(customValue) || customValue <= 0) {{
                alert('Please enter a valid positive number for radius.');
                return;
            }}
            currentRadius = customValue;
            document.getElementById('radius-value').textContent = customValue.toFixed(1);
            document.getElementById('radius-value-all').textContent = customValue.toFixed(1);
            
            // Update active button
            document.querySelectorAll('.radius-btn').forEach(function(btn) {{
                btn.classList.remove('active');
            }});
            
            if (radiusModeType === 'all-spbun') {{
                // All SPBUN mode - apply immediately
                applyRadiusFilter();
            }} else {{
                // Single point mode - need reference point
                if (radiusReferencePoint) {{
                    applyRadiusFilter();
                }} else {{
                    alert('Please click on the map or an SPBUN marker to set a reference point first.');
                }}
            }}
        }}
        
        // Apply radius filter
        function applyRadiusFilter() {{
            if (currentRadius === null || !map || !updateMarkerVisibility) return;
            
            if (radiusModeType === 'single') {{
                // Single point mode
                if (!radiusReferencePoint) return;
                
                var refLat = radiusReferencePoint.lat;
                var refLon = radiusReferencePoint.lon;
                
                // Draw/update circle
                if (radiusCircle) {{
                    map.removeLayer(radiusCircle);
                }}
                radiusCircle = L.circle([refLat, refLon], {{
                    radius: currentRadius * 1000, // Convert km to meters
                    color: '#f39c12',
                    fillColor: '#f39c12',
                    fillOpacity: 0.2,
                    weight: 2
                }}).addTo(map);
                
                // Update marker visibility first to apply the filter
                updateMarkerVisibility();
                
                // Count SPBU within radius after filtering
                var spbuCount = 0;
                spbuMarkers.forEach(function(marker) {{
                    var markerData = marker.options.data;
                    var distance = calculateDistance(refLat, refLon, markerData.lat, markerData.lon);
                    if (distance <= currentRadius) {{
                        // Check if marker is actually visible (passes all other filters too)
                        if (map.hasLayer(marker)) {{
                            spbuCount++;
                        }}
                    }}
                }});
                
                document.getElementById('radius-count').textContent = spbuCount;
                
                // Show info panel
                document.getElementById('radius-info').style.display = 'block';
                
            }} else {{
                // All SPBUN mode
                // Clear existing circles
                allSpbunCircles.forEach(function(circle) {{
                    map.removeLayer(circle);
                }});
                allSpbunCircles = [];
                
                // Get filter states to determine which SPBUN to use
                var selectedTipe = Array.from(document.querySelectorAll('.tipe-filter:checked')).map(cb => cb.value);
                var selectedMOR = Array.from(document.querySelectorAll('.mor-filter:checked')).map(cb => cb.value);
                var selectedProvinsi = Array.from(document.querySelectorAll('.provinsi-filter:checked')).map(cb => cb.value);
                var selectedKawasan = Array.from(document.querySelectorAll('.kawasan-filter:checked')).map(cb => cb.value);
                
                // Create circles for all SPBUN markers that pass filters
                // Note: We use SPBUN that pass Tipe, MOR, Provinsi, Kawasan filters
                // but don't require the "Show SPBUN" checkbox to be checked
                var spbunCount = 0;
                spbunMarkers.forEach(function(spbunMarker) {{
                    var spbunData = spbunMarker.options.data;
                    // Check if SPBUN passes filters
                    var spbunPasses = true;
                    if (selectedTipe.length > 0) {{
                        if (!selectedTipe.includes(spbunData.tipe_spbun)) spbunPasses = false;
                    }}
                    if (spbunPasses && selectedMOR.length > 0) {{
                        var morStr = String(spbunData.mor || '').trim();
                        var morInt = morStr;
                        if (morStr && !isNaN(parseFloat(morStr))) {{
                            morInt = String(parseInt(parseFloat(morStr)));
                        }}
                        if (!selectedMOR.includes(morStr) && !selectedMOR.includes(morInt)) spbunPasses = false;
                    }}
                    if (spbunPasses && selectedProvinsi.length > 0) {{
                        if (!selectedProvinsi.includes(spbunData.provinsi)) spbunPasses = false;
                    }}
                    if (spbunPasses && selectedKawasan.length > 0) {{
                        if (!selectedKawasan.includes(spbunData.kawasan)) spbunPasses = false;
                    }}
                    
                    if (spbunPasses) {{
                        var circle = L.circle([spbunData.lat, spbunData.lon], {{
                            radius: currentRadius * 1000, // Convert km to meters
                            color: '#3498db',
                            fillColor: '#3498db',
                            fillOpacity: 0.15,
                            weight: 2
                        }}).addTo(map);
                        allSpbunCircles.push(circle);
                        spbunCount++;
                    }}
                }});
                
                // Update marker visibility to apply the filter
                updateMarkerVisibility();
                
                // Count SPBU within radius of any SPBUN (after filtering)
                var spbuCount = 0;
                spbuMarkers.forEach(function(spbuMarker) {{
                    if (map.hasLayer(spbuMarker)) {{
                        spbuCount++;
                    }}
                }});
                
                // Show info panel
                document.getElementById('radius-info').style.display = 'block';
                document.getElementById('spbun-count').textContent = spbunCount; // Number of SPBUN used as reference points
                document.getElementById('radius-count-all').textContent = spbuCount; // Number of SPBU within radius
                document.getElementById('radius-value-all').textContent = currentRadius;
            }}
        }}
        
        // Clear radius filter
        function clearRadiusFilter() {{
            radiusReferencePoint = null;
            currentRadius = null;
            
            if (map) {{
                if (radiusCircle) {{
                    map.removeLayer(radiusCircle);
                    radiusCircle = null;
                }}
                
                if (radiusMarker) {{
                    map.removeLayer(radiusMarker);
                    radiusMarker = null;
                }}
                
                // Clear all SPBUN circles
                allSpbunCircles.forEach(function(circle) {{
                    map.removeLayer(circle);
                }});
                allSpbunCircles = [];
            }}
            
            document.getElementById('radius-info').style.display = 'none';
            document.getElementById('custom-radius').value = '';
            document.querySelectorAll('.radius-btn').forEach(function(btn) {{
                btn.classList.remove('active');
            }});
            
            if (updateMarkerVisibility) {{
                updateMarkerVisibility();
            }}
        }}
        
        
        console.log('Starting map initialization...');
        
        try {{
            // Initialize map centered on Indonesia
            map = L.map('map').setView([{avg_lat}, {avg_lon}], 5);
            console.log('Map created');
            
            // Create base layers
            var osmLayer = L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{
                attribution: '© OpenStreetMap contributors',
                maxZoom: 19
            }});
            
            var satelliteLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{{z}}/{{y}}/{{x}}', {{
                attribution: '© Esri &mdash; Source: Esri, Maxar, GeoEye, Earthstar Geographics, CNES/Airbus DS, USDA, USGS, AeroGRID, IGN, and the GIS User Community',
                maxZoom: 19
            }});
            
            // Add default layer
            osmLayer.addTo(map);
            console.log('Tile layer added');
            
            // Add layer control
            var baseMaps = {{
                "Map": osmLayer,
                "Satellite": satelliteLayer
            }};
            
            var layerControl = L.control.layers(baseMaps, null, {{
                position: 'topright'
            }}).addTo(map);
            
            // Adjust position to be below the sidebar toggle button
            var layerControlElement = document.querySelector('.leaflet-top.leaflet-right');
            if (layerControlElement) {{
                layerControlElement.style.top = '60px';
            }}
            
            console.log('Layer control added');
            
            // Add map click handler for radius filter reference point
            map.on('click', function(e) {{
                if (radiusModeActive) {{
                    setReferencePoint(e.latlng.lat, e.latlng.lng, null);
                }}
            }});
            
            // Add Indonesia GeoJSON boundary - load asynchronously to not block rendering
            setTimeout(function() {{
                try {{
                    var indonesiaGeoJSON = {json.dumps(indonesia_geojson)};
                    console.log('GeoJSON loaded, features:', indonesiaGeoJSON.features ? indonesiaGeoJSON.features.length : 'unknown');
                    
                    var indonesiaLayer = L.geoJSON(indonesiaGeoJSON, {{
                        style: {{
                            fillColor: '#e8f4f8',
                            fillOpacity: 0.3,
                            color: '#0066cc',
                            weight: 2,
                            opacity: 0.8
                        }},
                        onEachFeature: function(feature, layer) {{
                            layer.on({{
                                mouseover: function(e) {{
                                    var layer = e.target;
                                    layer.setStyle({{
                                        fillOpacity: 0.5,
                                        weight: 3
                                    }});
                                }},
                                mouseout: function(e) {{
                                    indonesiaLayer.resetStyle(e.target);
                                }}
                            }});
                        }}
                    }}).addTo(map);
                    console.log('Indonesia boundary layer added');
                }} catch (geoError) {{
                    console.error('Error loading GeoJSON:', geoError);
                    console.log('Continuing without Indonesia boundary overlay');
                }}
            }}, 500);
        
            
            // Marker data is already in global scope
            console.log('Markers data loaded:', markersData.length, 'locations');
            
            // Initialize color maps first
            var tipeValues = {json.dumps(tipe_spbun_values, ensure_ascii=False)};
            var morValues = {json.dumps(mor_values, ensure_ascii=False)};
            var provinsiValues = {json.dumps(provinsi_values, ensure_ascii=False)};
            var kawasanValues = {json.dumps(kawasan_values, ensure_ascii=False)};
            
            createColorMap('tipe', tipeValues);
            createColorMap('mor', morValues);
            createColorMap('provinsi', provinsiValues);
            createColorMap('kawasan', kawasanValues);
            
            // Add markers - separate arrays for filtering
            allMarkers = [];
            spbuMarkers = [];
            spbunMarkers = [];
            
            markersData.forEach(function(data) {{
                try {{
                    // Choose icon based on classification and color mode
                    var classification = data.classification || 'SPBUN';
                    var color = getMarkerColor(data);
                    var icon = createColoredIcon(color, classification === 'SPBU');
                    
                    var marker = L.marker([data.lat, data.lon], {{
                        icon: icon
                    }});
                    
                    // Create popup content based on classification
                    var title = classification + ' #' + data.no;
                    var popupContent = '<div class="custom-popup">' +
                        '<h4>' + title + '</h4>' +
                        '<div class="detail-row"><span class="label">MOR:</span> <span class="value">' + (data.mor || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Kawasan:</span> <span class="value">' + (data.kawasan || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Provinsi:</span> <span class="value">' + (data.provinsi || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Nama Badan Usaha:</span> <span class="value">' + (data.nama_badan_usaha || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Badan Usaha:</span> <span class="value">' + (data.badan_usaha || '') + '</span></div>';
                    
                    // Add SPBUN-specific fields only for SPBUN
                    if (classification === 'SPBUN') {{
                        popupContent += '<div class="detail-row"><span class="label">Tipe SPBUN:</span> <span class="value">' + (data.tipe_spbun || '') + '</span></div>' +
                            '<div class="detail-row"><span class="label">Jenis Kepemilikan:</span> <span class="value">' + (data.jenis_kepemilikan || '') + '</span></div>';
                    }}
                    
                    popupContent += '<div class="detail-row"><span class="label">Kabupaten/Kota:</span> <span class="value">' + (data.kabupaten || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Kecamatan:</span> <span class="value">' + (data.kecamatan || '') + '</span></div>' +
                        '<div class="detail-row"><span class="label">Alamat:</span> <span class="value">' + (data.alamat || '') + '</span></div>';
                    
                    // Add SPBUN-specific fields
                    if (classification === 'SPBUN') {{
                        popupContent += '<div class="detail-row"><span class="label">Pelabuhan:</span> <span class="value">' + (data.pelabuhan || '') + '</span></div>' +
                            '<div class="detail-row"><span class="label">Laut/Sungai:</span> <span class="value">' + (data.laut_sungai || '') + '</span></div>';
                    }}
                    
                    popupContent += '<div class="detail-row"><span class="label">SPBU Sekitar:</span> <span class="value">' + (data.spbu_sekitar || '') + ' Km</span></div>' +
                        '<div class="detail-row"><span class="label">Koordinat:</span> <span class="value">' + data.lat + ', ' + data.lon + '</span></div>' +
                        '</div>';
                    
                    // Create tooltip (hover)
                    var tooltipContent = '<strong>' + title + '</strong><br/>' +
                        (data.nama_badan_usaha || '') + '<br/>' +
                        (data.provinsi || '') + ' - ' + (data.kabupaten || '');
                    
                    marker.bindPopup(popupContent, {{
                        maxWidth: 400,
                        className: 'custom-popup-container'
                    }});
                    
                    marker.bindTooltip(tooltipContent, {{
                        permanent: false,
                        direction: 'top',
                        offset: [0, -10],
                        className: 'custom-tooltip'
                    }});
                    
                    // Add click handler for SPBUN markers to set reference point for radius filter
                    if (classification === 'SPBUN') {{
                        marker.on('click', function(e) {{
                            if (radiusModeActive) {{
                                setReferencePoint(data.lat, data.lon, data);
                                e.originalEvent.stopPropagation();
                            }}
                        }});
                    }}
                    
                    // Add to map initially
                    marker.addTo(map);
                    
                    // Store in appropriate arrays
                    allMarkers.push(marker);
                    if (classification === 'SPBU') {{
                        spbuMarkers.push(marker);
                    }} else {{
                        spbunMarkers.push(marker);
                    }}
                }} catch (markerError) {{
                    console.error('Error adding marker:', markerError, data);
                }}
            }});
            
            console.log('Markers added - SPBU:', spbuMarkers.length, 'SPBUN:', spbunMarkers.length);
            
            // Filter functionality
            updateMarkerVisibility = function() {{
                var showSPBU = document.getElementById('filter-spbu').checked;
                var showSPBUN = document.getElementById('filter-spbun').checked;
                
                // Get selected filter values
                var selectedTipe = Array.from(document.querySelectorAll('.tipe-filter:checked')).map(cb => cb.value);
                var selectedMOR = Array.from(document.querySelectorAll('.mor-filter:checked')).map(cb => cb.value);
                var selectedProvinsi = Array.from(document.querySelectorAll('.provinsi-filter:checked')).map(cb => cb.value);
                var selectedKawasan = Array.from(document.querySelectorAll('.kawasan-filter:checked')).map(cb => cb.value);
                
                // Update all markers visibility
                allMarkers.forEach(function(marker) {{
                    var markerData = marker.options.data;
                    var shouldShow = true;
                    var isRadiusFilteredSPBU = false; // Track if SPBU is shown due to radius filter
                    var isSPBUChecked = false; // Track if SPBU checkbox is checked for this marker
                    
                    // Filter by SPBU/SPBUN
                    if (markerData.classification === 'SPBU') {{
                        // If SPBU checkbox is checked, show all SPBU (radius filter should be disabled)
                        if (showSPBU) {{
                            shouldShow = true;
                            isSPBUChecked = true; // Mark that SPBU checkbox is checked
                        }} else if (radiusModeActive && currentRadius !== null) {{
                            // Only use radius filter if SPBU checkbox is not checked
                            if (radiusModeType === 'single') {{
                                // Single point mode
                                if (radiusReferencePoint) {{
                                    var distance = calculateDistance(
                                        radiusReferencePoint.lat, 
                                        radiusReferencePoint.lon,
                                        markerData.lat,
                                        markerData.lon
                                    );
                                    if (distance <= currentRadius) {{
                                        isRadiusFilteredSPBU = true;
                                        shouldShow = true;
                                    }} else {{
                                        shouldShow = false;
                                    }}
                                }} else {{
                                    shouldShow = false;
                                }}
                            }} else {{
                                // All SPBUN mode - check if SPBU is within radius of any SPBUN that passes filters
                                var withinRadius = false;
                                spbunMarkers.forEach(function(spbunMarker) {{
                                    var spbunData = spbunMarker.options.data;
                                    // Check SPBUN that pass other filters (Tipe, MOR, Provinsi, Kawasan)
                                    var spbunPassesFilters = true;
                                    if (selectedTipe.length > 0) {{
                                        if (!selectedTipe.includes(spbunData.tipe_spbun)) spbunPassesFilters = false;
                                    }}
                                    if (spbunPassesFilters && selectedMOR.length > 0) {{
                                        var morStr = String(spbunData.mor || '').trim();
                                        var morInt = morStr;
                                        if (morStr && !isNaN(parseFloat(morStr))) {{
                                            morInt = String(parseInt(parseFloat(morStr)));
                                        }}
                                        if (!selectedMOR.includes(morStr) && !selectedMOR.includes(morInt)) spbunPassesFilters = false;
                                    }}
                                    if (spbunPassesFilters && selectedProvinsi.length > 0) {{
                                        if (!selectedProvinsi.includes(spbunData.provinsi)) spbunPassesFilters = false;
                                    }}
                                    if (spbunPassesFilters && selectedKawasan.length > 0) {{
                                        if (!selectedKawasan.includes(spbunData.kawasan)) spbunPassesFilters = false;
                                    }}
                                    
                                    if (spbunPassesFilters) {{
                                        var distance = calculateDistance(
                                            spbunData.lat,
                                            spbunData.lon,
                                            markerData.lat,
                                            markerData.lon
                                        );
                                        if (distance <= currentRadius) {{
                                            withinRadius = true;
                                        }}
                                    }}
                                }});
                                if (withinRadius) {{
                                    isRadiusFilteredSPBU = true;
                                    shouldShow = true;
                                }} else {{
                                    shouldShow = false;
                                }}
                            }}
                        }} else {{
                            // No radius filter and checkbox not checked - hide SPBU
                            shouldShow = false;
                        }}
                    }} else if (markerData.classification === 'SPBUN') {{
                        // SPBUN markers - use normal checkbox
                        if (!showSPBUN) shouldShow = false;
                    }}
                    
                    // Apply other filters only if not already filtered out
                    // Skip filters for SPBU when SPBU checkbox is checked (show all SPBU)
                    if (shouldShow && !isRadiusFilteredSPBU && !isSPBUChecked) {{
                        // Filter by Tipe SPBUN (only applies to SPBUN)
                        if (markerData.classification === 'SPBUN' && selectedTipe.length > 0) {{
                            if (!selectedTipe.includes(markerData.tipe_spbun)) shouldShow = false;
                        }}
                        
                        // Filter by MOR (only apply to SPBUN or radius-filtered SPBU)
                        if (selectedMOR.length > 0) {{
                            var morStr = String(markerData.mor || '').trim();
                            // Also try converting to int in case of float values
                            var morInt = morStr;
                            if (morStr && !isNaN(parseFloat(morStr))) {{
                                morInt = String(parseInt(parseFloat(morStr)));
                            }}
                            if (!selectedMOR.includes(morStr) && !selectedMOR.includes(morInt)) shouldShow = false;
                        }}
                        
                        // Filter by Provinsi (only apply to SPBUN or radius-filtered SPBU)
                        if (selectedProvinsi.length > 0) {{
                            if (!selectedProvinsi.includes(markerData.provinsi)) shouldShow = false;
                        }}
                        
                        // Filter by Kawasan (only apply to SPBUN or radius-filtered SPBU)
                        if (selectedKawasan.length > 0) {{
                            if (!selectedKawasan.includes(markerData.kawasan)) shouldShow = false;
                        }}
                    }}
                    
                    if (shouldShow) {{
                        if (!map.hasLayer(marker)) {{
                            marker.addTo(map);
                        }}
                    }} else {{
                        if (map.hasLayer(marker)) {{
                            map.removeLayer(marker);
                        }}
                    }}
                }});
                
                // Update filtered data for table/download
                updateFilteredData();
            }}
            
            // Store marker data in marker options for filtering
            allMarkers.forEach(function(marker, index) {{
                marker.options.data = markersData[index];
            }});
            
            // Setup select all checkboxes
            setupSelectAll('tipe-all', 'tipe-filter');
            setupSelectAll('mor-all', 'mor-filter');
            setupSelectAll('provinsi-all', 'provinsi-filter');
            setupSelectAll('kawasan-all', 'kawasan-filter');
            
            // Setup color toggles (values already defined above)
            setupColorToggle('color-toggle-tipe', 'color-legend-tipe', 'tipe', tipeValues);
            setupColorToggle('color-toggle-mor', 'color-legend-mor', 'mor', morValues);
            setupColorToggle('color-toggle-provinsi', 'color-legend-provinsi', 'provinsi', provinsiValues);
            setupColorToggle('color-toggle-kawasan', 'color-legend-kawasan', 'kawasan', kawasanValues);
            
            // Add event listeners to checkboxes
            document.getElementById('filter-spbu').addEventListener('change', function() {{
                // If SPBU checkbox is checked, disable radius filter
                if (this.checked) {{
                    if (radiusModeActive) {{
                        radiusModeActive = false;
                        var btn = document.getElementById('radius-mode-btn');
                        var controls = document.getElementById('radius-controls');
                        btn.textContent = 'Enable Radius Filter';
                        btn.classList.remove('active');
                        controls.style.display = 'none';
                        document.getElementById('map').style.cursor = '';
                        // Clear radius filter
                        clearRadiusFilter();
                    }}
                }}
                // Always update marker visibility after checkbox change
                if (updateMarkerVisibility) {{
                    updateMarkerVisibility();
                }}
            }});
            document.getElementById('filter-spbun').addEventListener('change', updateMarkerVisibility);
            
            // Add event listeners to filter checkboxes
            document.querySelectorAll('.tipe-filter, .mor-filter, .provinsi-filter, .kawasan-filter').forEach(function(cb) {{
                cb.addEventListener('change', updateMarkerVisibility);
            }});
            
            // Add Enter key handler for custom radius input
            var customRadiusInput = document.getElementById('custom-radius');
            if (customRadiusInput) {{
                customRadiusInput.addEventListener('keypress', function(e) {{
                    if (e.key === 'Enter') {{
                        setCustomRadius();
                    }}
                }});
            }}
            
            // Add event listeners for radius mode radio buttons
            var radiusModeSingle = document.getElementById('radius-mode-single');
            var radiusModeAllSpbun = document.getElementById('radius-mode-all-spbun');
            if (radiusModeSingle) {{
                radiusModeSingle.addEventListener('change', updateRadiusModeUI);
            }}
            if (radiusModeAllSpbun) {{
                radiusModeAllSpbun.addEventListener('change', updateRadiusModeUI);
            }}
            
            // Apply default filter state (SPBU hidden by default)
            if (updateMarkerVisibility) {{
                updateMarkerVisibility();
            }}
            
            // Fit map to show all markers
            if (allMarkers.length > 0) {{
                try {{
                    var group = new L.featureGroup(allMarkers);
                    map.fitBounds(group.getBounds().pad(0.1));
                    console.log('Map bounds fitted to markers');
                }} catch (boundsError) {{
                    console.error('Error fitting bounds:', boundsError);
                }}
            }}
            
            console.log('Map initialized successfully with', markersData.length, 'locations');
        }} catch (error) {{
            console.error('Error initializing map:', error);
            alert('Error loading map. Please check the browser console for details.');
        }}
    </script>
</body>
</html>
"""

# Write HTML file
output_path = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/spbun_map_FIX.html"
with open(output_path, 'w', encoding='utf-8') as f:
    f.write(html_content)

print(f"\nInteractive map created successfully!")
print(f"Output file: {output_path}")
print(f"\nOpen the HTML file in your browser to view the map.")
