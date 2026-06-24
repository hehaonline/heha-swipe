import { useState } from "react";
import { supabase } from "../lib/supabase";

const GUEST_KEY = "heha.guest.location";

function loadGuestLocation() {
  try {
    const raw = localStorage.getItem(GUEST_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function saveGuestLocation(loc) {
  try {
    localStorage.setItem(GUEST_KEY, JSON.stringify(loc));
  } catch {
    // ignore
  }
}

export function getActiveLocationLabel(profileLocation) {
  if (profileLocation) return profileLocation;
  const guest = loadGuestLocation();
  if (guest?.label) return guest.label;
  if (guest?.city) return guest.city;
  return "Tampa Bay";
}

export default function LocationModal({ user, profileLocation, onClose, onLocationSaved }) {
  const [busy, setBusy] = useState(false);
  const [geoError, setGeoError] = useState(null);
  const [toast, setToast] = useState(null);
  const [form, setForm] = useState({
    label: "",
    street: "",
    city: "",
    state: "",
    zip: "",
  });

  const showToast = (msg) => {
    setToast(msg);
    window.setTimeout(() => setToast(null), 2800);
  };

  const updateForm = (field, value) => {
    setForm((prev) => ({ ...prev, [field]: value }));
  };

  const handleUseCurrentLocation = () => {
    if (!navigator.geolocation) {
      setGeoError("Geolocation is not supported by your browser.");
      return;
    }
    setBusy(true);
    setGeoError(null);
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const { latitude, longitude } = pos.coords;
        try {
          const res = await fetch(
            `https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}`,
            { headers: { "Accept-Language": "en" } }
          );
          const data = await res.json();
          const addr = data.address || {};
          setForm({
            label: addr.road
              ? `${addr.house_number ? addr.house_number + " " : ""}${addr.road}`
              : addr.suburb || addr.city || "My Location",
            street: addr.road
              ? `${addr.house_number ? addr.house_number + " " : ""}${addr.road}`
              : "",
            city: addr.city || addr.town || addr.village || addr.county || "",
            state: addr.state || "",
            zip: addr.postcode || "",
          });
        } catch {
          setGeoError("Could not reverse-geocode your location. Please enter manually.");
        } finally {
          setBusy(false);
        }
      },
      (err) => {
        setBusy(false);
        if (err.code === err.PERMISSION_DENIED) {
          setGeoError("Location access was denied. Please enter your address manually.");
        } else {
          setGeoError("Could not get your location. Please enter manually.");
        }
      }
    );
  };

  const buildLocationString = () => {
    const parts = [form.street, form.city, form.state, form.zip].filter(Boolean);
    return parts.length ? parts.join(", ") : form.label.trim();
  };

  const handleSave = async () => {
    const locationString = buildLocationString();
    const displayLabel = form.label.trim() || form.city || locationString;
    if (!locationString) {
      showToast("Please enter at least a city or street address.");
      return;
    }
    setBusy(true);
    try {
      if (user?.id) {
        const { error } = await supabase.from("profiles").upsert({
          id: user.id,
          location: locationString,
          updated_at: new Date().toISOString(),
        });
        if (error) throw error;
        showToast("Location saved to your profile.");
      } else {
        saveGuestLocation({ label: displayLabel, street: form.street, city: form.city, state: form.state, zip: form.zip });
        showToast("Location saved locally.");
      }
      onLocationSaved?.(locationString, displayLabel);
      window.setTimeout(() => onClose?.(), 700);
    } catch (err) {
      showToast(err.message || "Could not save location.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      className="location-modal-backdrop"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-label="Set your location"
    >
      <div className="location-modal-sheet" onClick={(e) => e.stopPropagation()}>
        <div className="location-modal-header">
          <h2>Set your location</h2>
          <button className="location-modal-close" onClick={onClose} aria-label="Close">x</button>
        </div>

        {toast && <div className="location-toast">{toast}</div>}

        <button
          className="location-geo-btn"
          onClick={handleUseCurrentLocation}
          disabled={busy}
        >
          <span>Location</span>
          {busy ? "Detecting location..." : "Use my current location"}
        </button>

        {geoError && <p className="location-geo-error">{geoError}</p>}

        <div className="location-divider"><span>or enter manually</span></div>

        <div className="location-form">
          <label className="location-field">
            <span>Label (optional)</span>
            <input
              value={form.label}
              onChange={(e) => updateForm("label", e.target.value)}
              placeholder="Home, Office, etc."
            />
          </label>
          <label className="location-field">
            <span>Street address</span>
            <input
              value={form.street}
              onChange={(e) => updateForm("street", e.target.value)}
              placeholder="123 Main St"
              autoComplete="street-address"
            />
          </label>
          <label className="location-field">
            <span>City</span>
            <input
              value={form.city}
              onChange={(e) => updateForm("city", e.target.value)}
              placeholder="Tampa"
              autoComplete="address-level2"
            />
          </label>
          <div className="location-row">
            <label className="location-field">
              <span>State</span>
              <input
                value={form.state}
                onChange={(e) => updateForm("state", e.target.value)}
                placeholder="FL"
                autoComplete="address-level1"
                maxLength={2}
              />
            </label>
            <label className="location-field">
              <span>ZIP</span>
              <input
                value={form.zip}
                onChange={(e) => updateForm("zip", e.target.value)}
                placeholder="33601"
                autoComplete="postal-code"
                maxLength={10}
              />
            </label>
          </div>
        </div>

        <button
          className="location-save-btn"
          onClick={handleSave}
          disabled={busy}
        >
          {busy ? "Saving..." : "Save location"}
        </button>

        <p className="location-note">
          {user?.id
            ? "Saved to your HEHA profile for future orders and recommendations."
            : "Saved locally on this device. Sign in to sync across devices."}
        </p>
      </div>
    </div>
  );
}
