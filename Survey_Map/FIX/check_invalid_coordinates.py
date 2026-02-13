import pandas as pd
import os

# Read the Excel file
excel_path = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/FIX/SPBUN_Terpilih.xlsx"

# Read from the 'SPBUN Terpilih' sheet
try:
    df = pd.read_excel(excel_path, sheet_name='SPBUN Terpilih')
except:
    # Fallback to first sheet if 'SPBUN Terpilih' sheet doesn't exist
    df = pd.read_excel(excel_path, sheet_name=0)

print(f"Total rows in Excel: {len(df)}")
print(f"\nColumn names: {list(df.columns)}")
print("\n" + "="*80)

# Parse coordinates from the "Koordinat" column
def parse_coordinates(coord_str, row_index):
    """Parse coordinates from string format 'lat,lon' to [lat, lon]"""
    result = {
        'valid': False,
        'error': None,
        'lat': None,
        'lon': None,
        'original_value': coord_str
    }
    
    if pd.isna(coord_str):
        result['error'] = 'Empty/NaN value'
        return result
    
    coord_str = str(coord_str).strip()
    
    # Check if it's empty after stripping
    if not coord_str or coord_str == '':
        result['error'] = 'Empty string'
        return result
    
    # Check if it contains comma
    if ',' not in coord_str:
        result['error'] = 'No comma found (expected format: lat,lon)'
        return result
    
    try:
        parts = coord_str.split(',')
        
        if len(parts) != 2:
            result['error'] = f'Invalid format: expected 2 parts separated by comma, got {len(parts)} parts'
            return result
        
        lat_str = parts[0].strip()
        lon_str = parts[1].strip()
        
        # Check if parts are empty
        if not lat_str or not lon_str:
            result['error'] = 'Empty latitude or longitude after splitting'
            return result
        
        # Try to convert to float
        try:
            lat = float(lat_str)
        except ValueError:
            result['error'] = f'Invalid latitude: "{lat_str}" cannot be converted to float'
            return result
        
        try:
            lon = float(lon_str)
        except ValueError:
            result['error'] = f'Invalid longitude: "{lon_str}" cannot be converted to float'
            return result
        
        # Validate coordinates are reasonable for Indonesia
        if lat < -15 or lat > 10:
            result['error'] = f'Latitude out of range for Indonesia: {lat} (expected -15 to 10)'
            result['lat'] = lat
            result['lon'] = lon
            return result
        
        if lon < 95 or lon > 145:
            result['error'] = f'Longitude out of range for Indonesia: {lon} (expected 95 to 145)'
            result['lat'] = lat
            result['lon'] = lon
            return result
        
        # Valid coordinates
        result['valid'] = True
        result['lat'] = lat
        result['lon'] = lon
        return result
        
    except Exception as e:
        result['error'] = f'Unexpected error: {str(e)}'
        return result

# Check all coordinates
invalid_rows = []
valid_count = 0

print("\nChecking coordinates...\n")

for idx, row in df.iterrows():
    coord_value = row.get('Koordinat', None)
    parse_result = parse_coordinates(coord_value, idx)
    
    if not parse_result['valid']:
        invalid_rows.append({
            'row_index': idx + 2,  # +2 because Excel is 1-indexed and has header
            'no': row.get('No  Lembaga Penyalur', 'N/A'),
            'classification': row.get('SPBU/SPBUN', 'N/A'),
            'nama_badan_usaha': row.get('Nama Badan Usaha', 'N/A'),
            'provinsi': row.get('Provinsi', 'N/A'),
            'kabupaten': row.get('Kabupaten/Kota', 'N/A'),
            'original_coordinate': parse_result['original_value'],
            'error': parse_result['error'],
            'lat': parse_result['lat'],
            'lon': parse_result['lon']
        })
    else:
        valid_count += 1

# Print summary
print("="*80)
print(f"SUMMARY:")
print(f"  Total rows: {len(df)}")
print(f"  Valid coordinates: {valid_count}")
print(f"  Invalid coordinates: {len(invalid_rows)}")
print("="*80)

# Print invalid coordinates details
if invalid_rows:
    print("\nINVALID COORDINATES DETAILS:\n")
    
    for i, invalid in enumerate(invalid_rows, 1):
        print(f"{i}. Row {invalid['row_index']} (Excel row {invalid['row_index']})")
        print(f"   No: {invalid['no']}")
        print(f"   Classification: {invalid['classification']}")
        print(f"   Nama Badan Usaha: {invalid['nama_badan_usaha']}")
        print(f"   Provinsi: {invalid['provinsi']}")
        print(f"   Kabupaten/Kota: {invalid['kabupaten']}")
        print(f"   Original Coordinate: {invalid['original_coordinate']}")
        print(f"   Error: {invalid['error']}")
        if invalid['lat'] is not None:
            print(f"   Parsed Lat: {invalid['lat']}")
        if invalid['lon'] is not None:
            print(f"   Parsed Lon: {invalid['lon']}")
        print()
    
    # Group by error type
    print("\n" + "="*80)
    print("ERRORS BY TYPE:\n")
    error_counts = {}
    for invalid in invalid_rows:
        error_type = invalid['error']
        if error_type not in error_counts:
            error_counts[error_type] = []
        error_counts[error_type].append(invalid['row_index'])
    
    for error_type, rows in sorted(error_counts.items(), key=lambda x: len(x[1]), reverse=True):
        print(f"{error_type}: {len(rows)} row(s)")
        print(f"  Rows: {', '.join(map(str, rows[:20]))}" + ("..." if len(rows) > 20 else ""))
        print()
    
    # Export to CSV for easy review
    invalid_df = pd.DataFrame(invalid_rows)
    output_csv = "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Survey_Map/FIX/invalid_coordinates_report.csv"
    invalid_df.to_csv(output_csv, index=False, encoding='utf-8-sig')
    print(f"\nDetailed report exported to: {output_csv}")
else:
    print("\n✓ All coordinates are valid!")

print("\n" + "="*80)

