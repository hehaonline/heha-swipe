export default function ScoutEventFields({ form, setForm }) {
  const set = (key) => (event) => setForm({ ...form, [key]: event.target.value });

  return (
    <section className="scout-event-fields">
      <div className="scout-section-heading compact">
        <div>
          <p className="internal-eyebrow">Event intelligence</p>
          <h3>Space & event details</h3>
        </div>
      </div>
      <div className="scout-form-grid">
        <label>Capacity<input value={form.event_capacity} onChange={set("event_capacity")} /></label>
        <label>Indoor / outdoor<input value={form.indoor_outdoor} onChange={set("indoor_outdoor")} /></label>
        <label className="wide">Parking<textarea value={form.parking_notes} onChange={set("parking_notes")} /></label>
        <label className="wide">Food vendor rules<textarea value={form.food_vendor_policy} onChange={set("food_vendor_policy")} /></label>
        <label className="wide">Alcohol rules<textarea value={form.alcohol_policy} onChange={set("alcohol_policy")} /></label>
        <label className="wide">Music / noise rules<textarea value={form.music_noise_policy} onChange={set("music_noise_policy")} /></label>
        <label>Power / electricity<textarea value={form.power_notes} onChange={set("power_notes")} /></label>
        <label>Bathrooms / restrooms<textarea value={form.restroom_notes} onChange={set("restroom_notes")} /></label>
        <label>Rental cost<textarea value={form.rental_cost_notes} onChange={set("rental_cost_notes")} /></label>
        <label>Availability / date windows<textarea value={form.availability_notes} onChange={set("availability_notes")} /></label>
      </div>
    </section>
  );
}
