import pandas as pd
import json
import os
import random
import math

# Read the Excel file
excel_path = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/lokasi_survei.xlsx"
df = pd.read_excel(excel_path, sheet_name='Calon-Survei')

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

# Filter only SPBUN locations
df_spbun = df_valid[df_valid['SPBU/SPBUN'].str.strip() == 'SPBUN'].copy()

print(f"Total rows: {len(df)}")
print(f"Rows with valid coordinates: {len(df_valid)}")
print(f"SPBUN locations: {len(df_spbun)}")

# Function to reclassify Badan Usaha
def reclassify_badan_usaha(badan_usaha_str):
    """Reclassify Badan Usaha into Koperasi or Perusahaan"""
    if pd.isna(badan_usaha_str) or not badan_usaha_str:
        return 'Perusahaan'
    badan_usaha_str = str(badan_usaha_str).strip()
    if badan_usaha_str in ['BUMD', 'Koperasi']:
        return 'Koperasi'
    else:
        return 'Perusahaan'

# Prepare marker data - only SPBUN
all_spbun_data = []
for idx, row in df_spbun.iterrows():
    badan_usaha_original = str(row['Badan Usaha']).strip() if pd.notna(row['Badan Usaha']) else ''
    badan_usaha_classified = reclassify_badan_usaha(row['Badan Usaha'])
    
    marker_info = {
        'lat': row['coords'][0],
        'lon': row['coords'][1],
        'no': row['No  Lembaga Penyalur'],
        'mor': row['MOR'],
        'kawasan': row['Kawasan'] if pd.notna(row['Kawasan']) else '',
        'provinsi': row['Provinsi'] if pd.notna(row['Provinsi']) else '',
        'kabupaten': row['Kabupaten/Kota'] if pd.notna(row['Kabupaten/Kota']) else '',
        'kecamatan': row['Kecamatan'] if pd.notna(row['Kecamatan']) else '',
        'nama_badan_usaha': row['Nama Badan Usaha'] if pd.notna(row['Nama Badan Usaha']) else '',
        'badan_usaha': badan_usaha_original,
        'badan_usaha_classified': badan_usaha_classified,
        'tipe_spbun': str(row['Tipe SPBUN']).strip() if pd.notna(row['Tipe SPBUN']) else '',
        'jenis_kepemilikan': row['Jenis Kepemilikan SPBUN'] if pd.notna(row['Jenis Kepemilikan SPBUN']) else '',
        'alamat': row['Alamat'] if pd.notna(row['Alamat']) else '',
        'pelabuhan': str(row['Pelabuhan (Pelabuhan & Non Pelabuhan)']).strip() if pd.notna(row['Pelabuhan (Pelabuhan & Non Pelabuhan)']) else '',
        'laut_sungai': str(row['Laut/Sungai']).strip() if pd.notna(row['Laut/Sungai']) else '',
        'spbu_sekitar': row['Keberadaan SPBU Sekitar (Km)'] if pd.notna(row['Keberadaan SPBU Sekitar (Km)']) else ''
    }
    all_spbun_data.append(marker_info)

# Get unique values for filters
tipe_spbun_values = sorted([str(v).strip() for v in df_spbun['Tipe SPBUN'].dropna().unique() if str(v).strip()])
badan_usaha_classified_values = ['Koperasi', 'Perusahaan']  # Use reclassified values
pelabuhan_values = sorted([str(v).strip() for v in df_spbun['Pelabuhan (Pelabuhan & Non Pelabuhan)'].dropna().unique() if str(v).strip()])

print(f"\nUnique Tipe SPBUN: {tipe_spbun_values}")
print(f"Unique Badan Usaha (Classified): {badan_usaha_classified_values}")
print(f"Unique Pelabuhan: {pelabuhan_values}")

# Also get all SPBU/SPBUN data for radius filtering
all_locations_data = []
for idx, row in df_valid.iterrows():
    classification = str(row['SPBU/SPBUN']).strip() if pd.notna(row['SPBU/SPBUN']) else 'SPBUN'
    marker_info = {
        'lat': row['coords'][0],
        'lon': row['coords'][1],
        'no': row['No  Lembaga Penyalur'],
        'classification': classification,
        'mor': row['MOR'],
        'provinsi': row['Provinsi'] if pd.notna(row['Provinsi']) else '',
        'kabupaten': row['Kabupaten/Kota'] if pd.notna(row['Kabupaten/Kota']) else '',
    }
    all_locations_data.append(marker_info)

# Calculate center point (average of all SPBUN coordinates)
if all_spbun_data:
    avg_lat = sum(m['lat'] for m in all_spbun_data) / len(all_spbun_data)
    avg_lon = sum(m['lon'] for m in all_spbun_data) / len(all_spbun_data)
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
    <title>SPBUN Survey Location Selector</title>
    
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
        
        .control-panel {{
            position: absolute;
            top: 10px;
            right: 10px;
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
            z-index: 1000;
            max-width: 350px;
            max-height: 90vh;
            overflow-y: auto;
            font-size: 13px;
        }}
        
        .control-panel h3 {{
            margin-top: 0;
            color: #333;
            font-size: 18px;
            border-bottom: 2px solid #3498db;
            padding-bottom: 8px;
        }}
        
        .control-section {{
            margin-top: 20px;
            padding-top: 15px;
            border-top: 1px solid #ddd;
        }}
        
        .control-section h4 {{
            margin-top: 0;
            margin-bottom: 10px;
            color: #555;
            font-size: 14px;
        }}
        
        .control-section label {{
            display: flex;
            align-items: center;
            margin: 6px 0;
            cursor: pointer;
        }}
        
        .control-section input[type="checkbox"] {{
            margin-right: 8px;
            cursor: pointer;
        }}
        
        .control-section input[type="range"] {{
            width: 100%;
            margin: 10px 0;
        }}
        
        .control-section select {{
            width: 100%;
            padding: 5px;
            margin: 5px 0;
            border: 1px solid #ddd;
            border-radius: 4px;
        }}
        
        .percentage-display {{
            font-weight: bold;
            color: #3498db;
            margin: 5px 0;
        }}
        
        .count-display {{
            font-weight: bold;
            color: #e74c3c;
            margin: 5px 0;
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
        
        .filter-group {{
            max-height: 300px;
            overflow-y: auto;
            border: 1px solid #eee;
            padding: 8px;
            border-radius: 4px;
            margin-top: 5px;
        }}
        
        .filter-group input[type="range"] {{
            margin: 5px 0;
        }}
        
        .filter-group input[type="range"]:disabled {{
            opacity: 0.5;
            cursor: not-allowed;
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
        <h3>Survey Location Selector</h3>
        <p><strong>Total SPBUN:</strong> {len(all_spbun_data)}</p>
        <div class="count-display">Selected: <span id="selected-count">{len(all_spbun_data)}</span> locations</div>
        
        <div class="control-section">
            <h4>Filter by Tipe SPBUN</h4>
            <div class="filter-group">
                <label>
                    <input type="checkbox" id="tipe-all" checked>
                    <strong>Select All</strong>
                </label>
                {''.join([f'<div style="margin: 8px 0; padding: 5px; background: #f8f9fa; border-radius: 4px;"><label style="display: block; margin-bottom: 5px;"><input type="checkbox" class="tipe-filter" value="{v}" checked>{v}</label><input type="range" class="tipe-percentage" data-value="{v}" min="0" max="100" value="100" step="1" style="width: 100%;"><div style="font-size: 11px; color: #3498db; margin-top: 3px;"><span class="tipe-percentage-value" data-value="{v}">100</span>%</div></div>' for v in tipe_spbun_values])}
            </div>
        </div>
        
        <div class="control-section">
            <h4>Filter by Badan Usaha</h4>
            <div class="filter-group">
                <label>
                    <input type="checkbox" id="badan-all" checked>
                    <strong>Select All</strong>
                </label>
                {''.join([f'<div style="margin: 8px 0; padding: 5px; background: #f8f9fa; border-radius: 4px;"><label style="display: block; margin-bottom: 5px;"><input type="checkbox" class="badan-filter" value="{v}" checked>{v}</label><input type="range" class="badan-percentage" data-value="{v}" min="0" max="100" value="100" step="1" style="width: 100%;"><div style="font-size: 11px; color: #3498db; margin-top: 3px;"><span class="badan-percentage-value" data-value="{v}">100</span>%</div></div>' for v in badan_usaha_classified_values])}
            </div>
        </div>
        
        <div class="control-section">
            <h4>Filter by Pelabuhan</h4>
            <div class="filter-group">
                <label>
                    <input type="checkbox" id="pelabuhan-all" checked>
                    <strong>Select All</strong>
                </label>
                {''.join([f'<div style="margin: 8px 0; padding: 5px; background: #f8f9fa; border-radius: 4px;"><label style="display: block; margin-bottom: 5px;"><input type="checkbox" class="pelabuhan-filter" value="{v}" checked>{v}</label><input type="range" class="pelabuhan-percentage" data-value="{v}" min="0" max="100" value="100" step="1" style="width: 100%;"><div style="font-size: 11px; color: #3498db; margin-top: 3px;"><span class="pelabuhan-percentage-value" data-value="{v}">100</span>%</div></div>' for v in pelabuhan_values])}
            </div>
        </div>
        
        <div class="control-section">
            <h4>Radius-Based Sampling</h4>
            <label>
                <input type="checkbox" id="enable-radius">
                Enable Radius Filter
            </label>
            <select id="radius-select" disabled>
                <option value="5">5 km</option>
                <option value="10">10 km</option>
                <option value="20">20 km</option>
                <option value="30">30 km</option>
            </select>
            <label style="margin-top: 10px;">
                <input type="checkbox" id="include-spbu" disabled>
                Include SPBU in radius
            </label>
            <label>
                <input type="checkbox" id="include-spbun" checked disabled>
                Include SPBUN in radius
            </label>
        </div>
        
        <div class="legend" style="margin-bottom: 20px;">
            <strong>Legend:</strong>
            <div class="legend-item">
                <div class="legend-color" style="background-color: #2ecc71;"></div>
                <span>Selected for Survey</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background-color: #95a5a6;"></div>
                <span>Filtered Out</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background-color: #e74c3c;"></div>
                <span>SPBU (if included)</span>
            </div>
        </div>
        
    </div>
    
    <script>
        // Global variables
        var currentView = 'map';
        var selectedDataForExport = [];
        var indonesiaLayer = null; // Store reference to Indonesia boundary layer
        
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
            
            if (selectedDataForExport.length === 0) {{
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
            selectedDataForExport.forEach(function(data) {{
                var row = document.createElement('tr');
                var values = [
                    data.no || '',
                    data.classification || 'SPBUN',
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
            
            // Remove Indonesia boundary layer (lines) before capturing
            var layerWasVisible = false;
            if (indonesiaLayer && map.hasLayer(indonesiaLayer)) {{
                map.removeLayer(indonesiaLayer);
                layerWasVisible = true;
            }}
            
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
                    // Restore Indonesia boundary layer if it was visible
                    if (layerWasVisible && indonesiaLayer) {{
                        indonesiaLayer.addTo(map);
                    }}
                    
                    // Restore UI elements
                    if (toolbar) toolbar.style.display = toolbarDisplay || '';
                    if (sidebar) sidebar.style.visibility = sidebarVisibility || '';
                    if (sidebarToggle) sidebarToggle.style.display = sidebarToggleDisplay || '';
                    
                    var link = document.createElement('a');
                    link.download = 'spbun_survey_map.png';
                    link.href = canvas.toDataURL('image/png');
                    link.click();
                }});
            }}, 100);
        }}
        
        function downloadCSV() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            var csv = 'No,Classification,MOR,Kawasan,Provinsi,Kabupaten/Kota,Kecamatan,Nama Badan Usaha,Badan Usaha,Tipe SPBUN,Jenis Kepemilikan,Alamat,Pelabuhan,Laut/Sungai,SPBU Sekitar,Latitude,Longitude\\n';
            
            selectedDataForExport.forEach(function(data) {{
                csv += [
                    data.no || '',
                    data.classification || 'SPBUN',
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
            link.download = 'spbun_survey_data.csv';
            link.click();
        }}
        
        function downloadGeoJSON() {{
            // Close dropdown
            document.getElementById('download-dropdown').classList.remove('show');
            
            var geojson = {{
                type: 'FeatureCollection',
                features: selectedDataForExport.map(function(data) {{
                    return {{
                        type: 'Feature',
                        geometry: {{
                            type: 'Point',
                            coordinates: [data.lon, data.lat]
                        }},
                        properties: {{
                            no: data.no,
                            classification: data.classification || 'SPBUN',
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
            link.download = 'spbun_survey_data.geojson';
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
            selectedDataForExport.forEach(function(data) {{
                ws_data.push([
                    data.no || '',
                    data.classification || 'SPBUN',
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
            XLSX.utils.book_append_sheet(wb, ws, 'Survey Data');
            XLSX.writeFile(wb, 'spbun_survey_data.xlsx');
        }}
        
        console.log('Starting map initialization...');
        
        // Haversine formula to calculate distance between two points
        function calculateDistance(lat1, lon1, lat2, lon2) {{
            var R = 6371; // Radius of the Earth in km
            var dLat = (lat2 - lat1) * Math.PI / 180;
            var dLon = (lon2 - lon1) * Math.PI / 180;
            var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                    Math.sin(dLon/2) * Math.sin(dLon/2);
            var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
            return R * c;
        }}
        
        try {{
            // Initialize map
            var map = L.map('map').setView([{avg_lat}, {avg_lon}], 5);
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
            
            // Add layer control - position it on top-right but below the sidebar toggle
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
            
            // Add Indonesia GeoJSON boundary
            setTimeout(function() {{
                try {{
                    var indonesiaGeoJSON = {json.dumps(indonesia_geojson)};
                    indonesiaLayer = L.geoJSON(indonesiaGeoJSON, {{
                        style: {{
                            fillColor: '#e8f4f8',
                            fillOpacity: 0.3,
                            color: '#0066cc',
                            weight: 2,
                            opacity: 0.8
                        }}
                    }}).addTo(map);
                    console.log('Indonesia boundary layer added');
                }} catch (geoError) {{
                    console.error('Error loading GeoJSON:', geoError);
                }}
            }}, 500);
            
            // All SPBUN data
            var allSPBUNData = {json.dumps(all_spbun_data, ensure_ascii=False)};
            // All locations (SPBU + SPBUN) for radius filtering
            var allLocationsData = {json.dumps(all_locations_data, ensure_ascii=False)};
            
            console.log('SPBUN data loaded:', allSPBUNData.length, 'locations');
            console.log('All locations data loaded:', allLocationsData.length, 'locations');
            
            // Create icons
            var selectedIcon = L.divIcon({{
                className: 'selected-marker',
                html: '<div style="background-color: #2ecc71; width: 14px; height: 14px; border-radius: 50%; border: 2px solid white; box-shadow: 0 2px 5px rgba(0,0,0,0.4);"></div>',
                iconSize: [14, 14],
                iconAnchor: [7, 7]
            }});
            
            var filteredIcon = L.divIcon({{
                className: 'filtered-marker',
                html: '<div style="background-color: #95a5a6; width: 12px; height: 12px; border-radius: 50%; border: 2px solid white; box-shadow: 0 2px 5px rgba(0,0,0,0.3); opacity: 0.5;"></div>',
                iconSize: [12, 12],
                iconAnchor: [6, 6]
            }});
            
            var spbuIcon = L.divIcon({{
                className: 'spbu-marker',
                html: '<div style="background-color: #e74c3c; width: 10px; height: 10px; border-radius: 50%; border: 2px solid white; box-shadow: 0 2px 5px rgba(0,0,0,0.3);"></div>',
                iconSize: [10, 10],
                iconAnchor: [5, 5]
            }});
            
            // Store all markers
            var allMarkers = [];
            var selectedMarkers = [];
            var filteredMarkers = [];
            var radiusMarkers = [];
            
            // Function to update map based on filters
            function updateMap() {{
                // Clear existing markers
                allMarkers.forEach(function(marker) {{
                    map.removeLayer(marker);
                }});
                selectedMarkers = [];
                filteredMarkers = [];
                radiusMarkers = [];
                
                // Get filter values
                var enableRadius = document.getElementById('enable-radius').checked;
                var radius = parseFloat(document.getElementById('radius-select').value);
                var includeSPBU = document.getElementById('include-spbu').checked;
                var includeSPBUN = document.getElementById('include-spbun').checked;
                
                // Get selected filter values
                var selectedTipe = Array.from(document.querySelectorAll('.tipe-filter:checked')).map(cb => cb.value);
                var selectedBadan = Array.from(document.querySelectorAll('.badan-filter:checked')).map(cb => cb.value);
                var selectedPelabuhan = Array.from(document.querySelectorAll('.pelabuhan-filter:checked')).map(cb => cb.value);
                
                // Get percentage values for each category
                var tipePercentages = {{}};
                document.querySelectorAll('.tipe-percentage').forEach(function(slider) {{
                    var value = slider.getAttribute('data-value');
                    tipePercentages[value] = parseFloat(slider.value);
                }});
                
                var badanPercentages = {{}};
                document.querySelectorAll('.badan-percentage').forEach(function(slider) {{
                    var value = slider.getAttribute('data-value');
                    badanPercentages[value] = parseFloat(slider.value);
                }});
                
                var pelabuhanPercentages = {{}};
                document.querySelectorAll('.pelabuhan-percentage').forEach(function(slider) {{
                    var value = slider.getAttribute('data-value');
                    pelabuhanPercentages[value] = parseFloat(slider.value);
                }});
                
                // Filter SPBUN data based on type filters
                var filteredData = allSPBUNData.filter(function(data) {{
                    var tipeMatch = selectedTipe.length === 0 || selectedTipe.includes(data.tipe_spbun);
                    var badanMatch = selectedBadan.length === 0 || selectedBadan.includes(data.badan_usaha_classified);
                    var pelabuhanMatch = selectedPelabuhan.length === 0 || selectedPelabuhan.includes(data.pelabuhan);
                    return tipeMatch && badanMatch && pelabuhanMatch;
                }});
                
                console.log('After type filters:', filteredData.length, 'locations');
                
                // Group by Tipe SPBUN, Badan Usaha (classified), and Pelabuhan
                var groups = {{}};
                filteredData.forEach(function(data) {{
                    var groupKey = data.tipe_spbun + '|' + data.badan_usaha_classified + '|' + data.pelabuhan;
                    if (!groups[groupKey]) {{
                        groups[groupKey] = [];
                    }}
                    groups[groupKey].push(data);
                }});
                
                console.log('Number of groups:', Object.keys(groups).length);
                
                // Apply matched percentage sampling within each group
                // Use minimum percentage from the three categories (matched sampling)
                var sampledData = [];
                Object.keys(groups).forEach(function(groupKey) {{
                    var groupData = groups[groupKey];
                    var parts = groupKey.split('|');
                    var tipe = parts[0];
                    var badan = parts[1];
                    var pelabuhan = parts[2];
                    
                    // Get percentages for this group's attributes (only if category is selected)
                    var percentages = [];
                    if (selectedTipe.includes(tipe)) {{
                        percentages.push(tipePercentages[tipe] || 100);
                    }}
                    if (selectedBadan.includes(badan)) {{
                        percentages.push(badanPercentages[badan] || 100);
                    }}
                    if (selectedPelabuhan.includes(pelabuhan)) {{
                        percentages.push(pelabuhanPercentages[pelabuhan] || 100);
                    }}
                    
                    // Use minimum percentage (matched sampling) - default to 100% if no percentages
                    var matchedPercentage = percentages.length > 0 ? Math.min.apply(null, percentages) : 100;
                    
                    var groupSampleSize = Math.round(groupData.length * matchedPercentage / 100);
                    if (groupSampleSize > 0) {{
                        // Random sampling within group
                        var shuffled = groupData.slice().sort(() => 0.5 - Math.random());
                        sampledData = sampledData.concat(shuffled.slice(0, groupSampleSize));
                    }}
                }});
                
                console.log('After matched percentage sampling (grouped):', sampledData.length, 'locations');
                
                // Apply radius filtering if enabled
                var finalSelectedData = [];
                if (enableRadius && sampledData.length > 0) {{
                    // For each selected location, find locations within radius
                    var processedLocations = new Set();
                    sampledData.forEach(function(centerLocation) {{
                        var centerKey = centerLocation.lat + ',' + centerLocation.lon;
                        if (processedLocations.has(centerKey)) return;
                        
                        var locationsInRadius = [];
                        
                        // Check all locations (SPBU + SPBUN)
                        allLocationsData.forEach(function(loc) {{
                            var distance = calculateDistance(
                                centerLocation.lat, centerLocation.lon,
                                loc.lat, loc.lon
                            );
                            
                            if (distance <= radius) {{
                                var include = false;
                                if (loc.classification === 'SPBU' && includeSPBU) {{
                                    include = true;
                                }} else if (loc.classification === 'SPBUN' && includeSPBUN) {{
                                    include = true;
                                }}
                                
                                if (include) {{
                                    locationsInRadius.push(loc);
                                    processedLocations.add(loc.lat + ',' + loc.lon);
                                }}
                            }}
                        }});
                        
                        // Add center location if it's SPBUN and included
                        if (includeSPBUN) {{
                            locationsInRadius.push(centerLocation);
                            processedLocations.add(centerKey);
                        }}
                        
                        finalSelectedData = finalSelectedData.concat(locationsInRadius);
                    }});
                    
                    // Remove duplicates
                    var uniqueData = [];
                    var seen = new Set();
                    finalSelectedData.forEach(function(loc) {{
                        var key = loc.lat + ',' + loc.lon;
                        if (!seen.has(key)) {{
                            seen.add(key);
                            uniqueData.push(loc);
                        }}
                    }});
                    finalSelectedData = uniqueData;
                }} else {{
                    finalSelectedData = sampledData;
                }}
                
                console.log('Final selected locations:', finalSelectedData.length);
                
                // Update count display
                document.getElementById('selected-count').textContent = finalSelectedData.length;
                
                // Add markers for filtered out locations (gray)
                filteredData.forEach(function(data) {{
                    var isSelected = finalSelectedData.some(function(sel) {{
                        return sel.lat === data.lat && sel.lon === data.lon;
                    }});
                    
                    if (!isSelected) {{
                        var marker = L.marker([data.lat, data.lon], {{
                            icon: filteredIcon
                        }});
                        
                        var popupContent = createPopupContent(data, 'SPBUN');
                        marker.bindPopup(popupContent, {{ maxWidth: 400 }});
                        marker.addTo(map);
                        filteredMarkers.push(marker);
                        allMarkers.push(marker);
                    }}
                }});
                
                // Add markers for selected locations (green)
                finalSelectedData.forEach(function(data) {{
                    var icon = (data.classification === 'SPBU') ? spbuIcon : selectedIcon;
                    var marker = L.marker([data.lat, data.lon], {{
                        icon: icon
                    }});
                    
                    var popupContent = createPopupContent(data, data.classification || 'SPBUN');
                    marker.bindPopup(popupContent, {{ maxWidth: 400 }});
                    marker.addTo(map);
                    selectedMarkers.push(marker);
                    allMarkers.push(marker);
                }});
                
                // Store selected data for export/table (all selected locations)
                selectedDataForExport = finalSelectedData;
                
                // Update table if in table view
                if (currentView === 'table') {{
                    renderTable();
                }}
                
                // Fit bounds to selected markers
                if (selectedMarkers.length > 0) {{
                    try {{
                        var group = new L.featureGroup(selectedMarkers);
                        map.fitBounds(group.getBounds().pad(0.1));
                    }} catch (boundsError) {{
                        console.error('Error fitting bounds:', boundsError);
                    }}
                }}
            }}
            
            function createPopupContent(data, classification) {{
                var title = classification + ' #' + data.no;
                var content = '<div class="custom-popup">' +
                    '<h4>' + title + '</h4>' +
                    '<div class="detail-row"><span class="label">MOR:</span> <span class="value">' + data.mor + '</span></div>';
                
                if (data.nama_badan_usaha) {{
                    content += '<div class="detail-row"><span class="label">Nama Badan Usaha:</span> <span class="value">' + data.nama_badan_usaha + '</span></div>';
                }}
                if (data.badan_usaha) {{
                    content += '<div class="detail-row"><span class="label">Badan Usaha:</span> <span class="value">' + data.badan_usaha + '</span></div>';
                }}
                if (data.tipe_spbun) {{
                    content += '<div class="detail-row"><span class="label">Tipe SPBUN:</span> <span class="value">' + data.tipe_spbun + '</span></div>';
                }}
                if (data.pelabuhan) {{
                    content += '<div class="detail-row"><span class="label">Pelabuhan:</span> <span class="value">' + data.pelabuhan + '</span></div>';
                }}
                if (data.provinsi) {{
                    content += '<div class="detail-row"><span class="label">Provinsi:</span> <span class="value">' + data.provinsi + '</span></div>';
                }}
                if (data.kabupaten) {{
                    content += '<div class="detail-row"><span class="label">Kabupaten/Kota:</span> <span class="value">' + data.kabupaten + '</span></div>';
                }}
                content += '<div class="detail-row"><span class="label">Koordinat:</span> <span class="value">' + data.lat + ', ' + data.lon + '</span></div>' +
                    '</div>';
                return content;
            }}
            
            // Event listeners for percentage sliders
            document.querySelectorAll('.tipe-percentage').forEach(function(slider) {{
                slider.addEventListener('input', function() {{
                    var value = this.getAttribute('data-value');
                    document.querySelector('.tipe-percentage-value[data-value="' + value + '"]').textContent = this.value;
                    updateMap();
                }});
            }});
            
            document.querySelectorAll('.badan-percentage').forEach(function(slider) {{
                slider.addEventListener('input', function() {{
                    var value = this.getAttribute('data-value');
                    document.querySelector('.badan-percentage-value[data-value="' + value + '"]').textContent = this.value;
                    updateMap();
                }});
            }});
            
            document.querySelectorAll('.pelabuhan-percentage').forEach(function(slider) {{
                slider.addEventListener('input', function() {{
                    var value = this.getAttribute('data-value');
                    document.querySelector('.pelabuhan-percentage-value[data-value="' + value + '"]').textContent = this.value;
                    updateMap();
                }});
            }});
            
            // Select all checkboxes
            function setupSelectAll(groupId, filterClass) {{
                var selectAll = document.getElementById(groupId);
                var filters = document.querySelectorAll('.' + filterClass);
                
                selectAll.addEventListener('change', function() {{
                    filters.forEach(function(cb) {{
                        cb.checked = this.checked;
                    }});
                    updateMap();
                }});
                
                filters.forEach(function(cb) {{
                    cb.addEventListener('change', function() {{
                        var allChecked = Array.from(filters).every(function(f) {{ return f.checked; }});
                        selectAll.checked = allChecked;
                        updateMap();
                    }});
                }});
            }}
            
            setupSelectAll('tipe-all', 'tipe-filter');
            setupSelectAll('badan-all', 'badan-filter');
            setupSelectAll('pelabuhan-all', 'pelabuhan-filter');
            
            // Enable/disable percentage sliders based on checkbox state
            function updatePercentageSliders() {{
                document.querySelectorAll('.tipe-filter').forEach(function(cb) {{
                    var value = cb.value;
                    var slider = document.querySelector('.tipe-percentage[data-value="' + value + '"]');
                    if (slider) slider.disabled = !cb.checked;
                }});
                
                document.querySelectorAll('.badan-filter').forEach(function(cb) {{
                    var value = cb.value;
                    var slider = document.querySelector('.badan-percentage[data-value="' + value + '"]');
                    if (slider) slider.disabled = !cb.checked;
                }});
                
                document.querySelectorAll('.pelabuhan-filter').forEach(function(cb) {{
                    var value = cb.value;
                    var slider = document.querySelector('.pelabuhan-percentage[data-value="' + value + '"]');
                    if (slider) slider.disabled = !cb.checked;
                }});
            }}
            
            // Update sliders when checkboxes change
            document.querySelectorAll('.tipe-filter, .badan-filter, .pelabuhan-filter').forEach(function(cb) {{
                cb.addEventListener('change', function() {{
                    updatePercentageSliders();
                    updateMap();
                }});
            }});
            
            // Initial update
            updatePercentageSliders();
            
            // Radius controls
            document.getElementById('enable-radius').addEventListener('change', function() {{
                var enabled = this.checked;
                document.getElementById('radius-select').disabled = !enabled;
                document.getElementById('include-spbu').disabled = !enabled;
                document.getElementById('include-spbun').disabled = !enabled;
                updateMap();
            }});
            
            document.getElementById('radius-select').addEventListener('change', updateMap);
            document.getElementById('include-spbu').addEventListener('change', updateMap);
            document.getElementById('include-spbun').addEventListener('change', updateMap);
            
            // Initial map update
            updateMap();
            
            console.log('Map initialized successfully');
        }} catch (error) {{
            console.error('Error initializing map:', error);
            alert('Error loading map. Please check the browser console for details.');
        }}
    </script>
</body>
</html>
"""

# Write HTML file
output_path = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/spbun_survey_map.html"
with open(output_path, 'w', encoding='utf-8') as f:
    f.write(html_content)

print(f"\nSurvey location selector map created successfully!")
print(f"Output file: {output_path}")
print(f"\nOpen the HTML file in your browser to view the map.")

